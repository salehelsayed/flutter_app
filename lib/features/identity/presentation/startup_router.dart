import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/debug/transport_metrics.dart';
import 'package:flutter_app/core/media/audio_recorder_service.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/notifications/app_root_notification_open.dart';
import 'package:flutter_app/core/notifications/ios_apns_notification_open_bridge.dart';
import 'package:flutter_app/core/notifications/notification_route_dispatch.dart';
import 'package:flutter_app/core/notifications/notification_route_target.dart';
import 'package:flutter_app/features/conversation/application/reaction_listener.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/retry_incomplete_group_downloads_use_case.dart';
import 'package:flutter_app/features/groups/application/group_invite_listener.dart';
import 'package:flutter_app/features/groups/application/group_pending_key_repair_service.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_exit_diagnostic_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_history_gap_repair_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_key_repair_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_reaction_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_reaction_replay_outbox_repository.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_presentation_gate.dart';
import 'package:flutter_app/features/contact_request/domain/repositories/contact_request_repository.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_authority_repository_impl.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_runtime_network_gate.dart';
import 'package:flutter_app/features/account_migration/application/migration_secure_storage_cleanup.dart';
import 'package:flutter_app/features/account_migration/application/migration_secure_storage_registry.dart';
import 'package:flutter_app/features/account_migration/application/migration_secure_storage_staging.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_transfer_flow.dart';
import 'package:flutter_app/features/account_migration/application/migration_account_size_estimator.dart';
import 'package:flutter_app/features/account_migration/application/migration_qr_payload_use_case.dart';
import 'package:flutter_app/features/account_migration/domain/models/account_migration_authority_state.dart';
import 'package:flutter_app/features/account_migration/presentation/screens/account_migration_blocked_screen.dart';
import 'package:flutter_app/features/account_migration/presentation/screens/account_migration_journey_wired.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/feed/presentation/screens/feed_wired.dart';
import 'package:flutter_app/features/settings/application/background_preference_use_cases.dart';
import 'package:flutter_app/features/identity/application/startup_decision.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/identity/presentation/navigation/startup_route_transition.dart';
import 'package:flutter_app/features/identity/presentation/screens/identity_choice_wired.dart';
import 'package:flutter_app/features/identity/presentation/widgets/startup_loading_gate.dart';
import 'package:flutter_app/features/home/presentation/screens/first_time_experience_wired.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_app/features/identity/application/linked_installation_authority.dart';
import 'package:flutter_app/features/p2p/application/start_node_use_case.dart';
import 'package:flutter_app/features/push/application/handle_initial_remote_message_use_case.dart';
import 'package:flutter_app/features/push/application/prepare_notification_route_target_use_case.dart';
import 'package:flutter_app/features/push/application/push_registration_coordinator.dart';
import 'package:flutter_app/core/utils/startup_timing.dart';
import 'package:flutter_app/core/config/startup_config.dart';
import 'package:flutter_app/features/groups/application/announce_restored_device_use_case.dart';
import 'package:flutter_app/features/groups/application/rejoin_group_topics_use_case.dart';
import 'package:flutter_app/features/groups/application/reconcile_missed_group_dissolves_use_case.dart';
import 'package:flutter_app/features/groups/application/drain_group_offline_inbox_use_case.dart';
import 'package:flutter_app/features/groups/application/group_recovery_gate.dart';
import 'package:flutter_app/features/introduction/domain/repositories/introduction_repository.dart';
import 'package:flutter_app/features/introduction/domain/repositories/intro_review_seen_repository.dart';
import 'package:flutter_app/features/introduction/application/introduction_listener.dart';
import 'package:flutter_app/core/services/share_intent_model.dart';
import 'package:flutter_app/core/services/share_intent_service.dart';
import 'package:flutter_app/features/share/application/settle_share_intent_flow.dart';
import 'package:flutter_app/features/share/presentation/navigation/share_target_picker_route.dart';
import 'package:flutter_app/features/share/presentation/screens/share_target_picker_wired.dart';
import 'package:flutter_app/features/feed/application/app_shell_controller.dart';
import 'package:flutter_app/features/posts/application/nearby_location_service.dart';
import 'package:flutter_app/features/posts/application/pending_post_target_store.dart';
import 'package:flutter_app/features/posts/application/refresh_nearby_on_startup_use_case.dart';
import 'package:flutter_app/features/posts/domain/repositories/contact_presence_snapshot_repository.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';
import 'package:flutter_app/features/posts/domain/repositories/posts_privacy_settings_repository.dart';
import 'package:flutter_app/features/feed/data/feed_cleared_repository.dart';

typedef _AccountMigrationOnboardingBuilder =
    Widget Function(
      BuildContext context,
      AccountMigrationReceiverStartFn? startReceiver,
      AccountMigrationReceiverStopFn? stopReceiver,
    );

class _AccountMigrationOnboardingActivationOwner extends StatefulWidget {
  final AccountMigrationReceiverStartFn? startReceiver;
  final AccountMigrationReceiverStopFn? stopReceiver;
  final AccountMigrationReceiverEvents? receiverEvents;
  final Future<void> Function()? refreshAfterActivation;
  final StartupRouter restartedStartupRouter;
  final _AccountMigrationOnboardingBuilder builder;

  const _AccountMigrationOnboardingActivationOwner({
    required this.startReceiver,
    required this.stopReceiver,
    required this.receiverEvents,
    required this.refreshAfterActivation,
    required this.restartedStartupRouter,
    required this.builder,
  });

  @override
  State<_AccountMigrationOnboardingActivationOwner> createState() =>
      _AccountMigrationOnboardingActivationOwnerState();
}

class _AccountMigrationOnboardingActivationOwnerState
    extends State<_AccountMigrationOnboardingActivationOwner> {
  StreamSubscription<AccountMigrationReceiverEvent>? _receiverEventsSub;
  String? _activeSessionId;
  bool _activationStarted = false;

  @override
  void initState() {
    super.initState();
    _receiverEventsSub = widget.receiverEvents?.listen(_handleReceiverEvent);
  }

  Future<AccountMigrationReceiverStartResult> _startReceiver(
    MigrationQrBuildOutput output,
  ) async {
    final result = await widget.startReceiver!(output);
    if (result.isStarted) {
      _activeSessionId = output.payload.sessionId;
      _activationStarted = false;
    }
    return result;
  }

  Future<void> _stopReceiver(String sessionId) async {
    await widget.stopReceiver?.call(sessionId);
    if (_activeSessionId == sessionId) {
      _activeSessionId = null;
    }
  }

  void _handleReceiverEvent(AccountMigrationReceiverEvent event) {
    if (event.type != AccountMigrationReceiverEventType.activated ||
        event.sessionId != _activeSessionId ||
        _activationStarted) {
      return;
    }
    _activationStarted = true;
    unawaited(_finishActivation(event.sessionId));
  }

  Future<void> _finishActivation(String sessionId) async {
    final refreshAfterActivation = widget.refreshAfterActivation;
    final restartedStartupRouter = widget.restartedStartupRouter;
    try {
      await _stopReceiver(sessionId);
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ACCOUNT_MIGRATION_RECEIVER_STOP_AFTER_ACTIVATION_FAILED',
        details: {'sessionId': sessionId, 'error': error.toString()},
      );
    }
    if (!mounted) return;

    try {
      await refreshAfterActivation?.call();
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ACCOUNT_MIGRATION_RECEIVER_ACTIVATION_REFRESH_FAILED',
        details: {'errorType': accountMigrationTransferErrorType(error)},
      );
    }
    if (!mounted) return;

    emitFlowEvent(
      layer: 'FL',
      event: 'ACCOUNT_MIGRATION_RECEIVER_ROUTE_RESET',
      details: {},
    );
    Navigator.of(context).pushAndRemoveUntil(
      buildStartupReplacementRoute<void>(
        settings: const RouteSettings(
          name: 'startup-router-after-account-migration',
        ),
        builder: (_) => restartedStartupRouter,
      ),
      (_) => false,
    );
  }

  @override
  void dispose() {
    unawaited(_receiverEventsSub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(
      context,
      widget.startReceiver == null ? null : _startReceiver,
      widget.startReceiver == null ? null : _stopReceiver,
    );
  }
}

/// Router widget that handles app startup navigation.
///
/// This widget is displayed at app startup and determines whether to
/// navigate to the main app (if an identity exists) or to the identity
/// onboarding flow (if no identity exists).
///
/// The widget shows a loading indicator while checking for an existing
/// identity, then uses pushReplacement to navigate to the appropriate
/// screen, ensuring a clean navigation stack.
class StartupRouter extends StatefulWidget {
  /// The repository used to check for existing identity.
  final IdentityRepository repository;

  /// The repository used to manage contacts.
  final ContactRepository contactRepository;

  /// The repository used to manage contact requests.
  final ContactRequestRepository contactRequestRepository;

  /// The listener for incoming contact requests.
  final ContactRequestListener contactRequestListener;

  /// The message repository for conversation persistence.
  final MessageRepository messageRepository;

  final PostRepository postRepository;

  /// The media attachment repository for media metadata.
  final MediaAttachmentRepository mediaAttachmentRepository;

  /// The listener for incoming chat messages.
  final ChatMessageListener chatMessageListener;

  /// The bridge instance for identity operations.
  final Bridge bridge;

  /// The P2P service for networking operations.
  final P2PService p2pService;

  /// NET-REL-04: session-scoped, aggregate-only transport diagnostics.
  final TransportMetrics? transportMetrics;

  /// The media file manager for local file operations.
  final MediaFileManager mediaFileManager;

  /// The secure key store for preference storage.
  final SecureKeyStore secureKeyStore;

  /// The image processor for EXIF stripping and compression.
  final ImageProcessor imageProcessor;

  /// Tracks which conversation is currently open (for notification suppression).
  final ActiveConversationTracker? conversationTracker;

  /// The audio recorder service for voice messages.
  final AudioRecorderService? audioRecorderService;

  /// The reaction repository for emoji reactions.
  final ReactionRepository? reactionRepository;

  /// The reaction listener for incoming reactions.
  final ReactionListener? reactionListener;

  /// The group repository for group persistence.
  final GroupRepository? groupRepository;

  /// The group message repository for group message persistence.
  final GroupMessageRepository? groupMessageRepository;

  /// Release-visible, bounded group-exit diagnostic history.
  final GroupExitDiagnosticRepository? groupExitDiagnosticRepository;

  /// Local invite delivery status repository for group invite UX.
  final GroupInviteDeliveryAttemptRepository?
  groupInviteDeliveryAttemptRepository;

  /// Durable queue for future/missing-key repair replay.
  final GroupPendingKeyRepairRepository? groupPendingKeyRepairRepository;

  /// Slice 2 / UDM-G — the real outbound active key-pull used by the post-rejoin
  /// offline-inbox drain. Defaults to the FLOW-log-only [emitGroupKeyRepairRequest]
  /// stub so tests/edge constructions remain backward-compatible.
  final RequestGroupKeyRepair? requestGroupKeyRepair;

  /// Durable lifecycle state for partial history gap repair.
  final GroupHistoryGapRepairRepository? groupHistoryGapRepairRepository;

  /// Durable sender-owned reaction replay outbox repository.
  final GroupReactionReplayOutboxRepository?
  groupReactionReplayOutboxRepository;

  /// Plan 322: durable buffer for a drained reaction whose target message has
  /// not landed yet. Without it the drain DROPS the reaction permanently.
  final GroupPendingReactionRepository? groupPendingReactionRepository;

  /// The group message listener for incoming group messages.
  final GroupMessageListener? groupMessageListener;
  final GroupMediaDownloadCoordinator? groupMediaDownloadCoordinator;

  /// Durable group-exit authority used by cold-start rejoin and recovery.
  final Future<bool> Function(String groupId)? canRejoinForExitIntent;
  final Future<void> Function(String groupId)? processExitIntent;
  final Future<void> Function()? groupExitIntentRecovery;

  /// The group invite listener for incoming group invites.
  final GroupInviteListener? groupInviteListener;

  /// Waits until direct group membership-update replay work is idle.
  final Future<void> Function()? waitForGroupMembershipUpdateIdle;

  /// Tracks which group conversation is currently open (for notification suppression).
  final ActiveConversationTracker? groupConversationTracker;

  /// The introduction repository for managing introductions.
  final IntroductionRepository? introductionRepository;

  /// Device-local seen set for the Orbit intro dock and nav badge.
  final IntroReviewSeenRepository? introReviewSeenRepository;

  /// The introduction listener for incoming introductions.
  final IntroductionListener? introductionListener;

  /// The share intent service for handling shared content from external apps.
  final ShareIntentService? shareIntentService;
  final Future<void>? initialShareIntentCapture;
  final Future<void> Function()? ensureRuntimeServicesReady;

  /// Dedicated-profile seam for replacing only the P2P node-start operation.
  /// Normal application startup continues to use [startP2PNode].
  final Future<StartNodeResult> Function()? startP2PNodeOverride;

  /// FDC-07: cold-start hook that starts LAN mDNS discovery early (ahead of the
  /// warmBackground inbox-drain body) so a same-WiFi peer can populate the LAN
  /// map before the first send window. Wired in main.dart to the concrete
  /// [P2PServiceImpl.startEarlyLocalDiscovery]; kept as an optional callback
  /// (NOT a [P2PService] interface method) so it adds no churn to the many
  /// `implements P2PService` fakes. Opportunistic + idempotent — invoked once
  /// node-start succeeds, after [ensureRuntimeServicesReady].
  final Future<void> Function()? startEarlyLocalDiscovery;

  final AppShellController appShellController;
  final PendingPostTargetStore pendingPostTargetStore;
  final PostsPrivacySettingsRepository postsPrivacySettingsRepository;
  final FeedClearedRepository feedClearedRepository;
  final ContactPresenceSnapshotRepository? contactPresenceSnapshotRepository;
  final NearbyLocationService? nearbyLocationService;
  final PushRegistrationCoordinator? pushRegistrationCoordinator;
  final ContactRequestPresentationGate? contactRequestPresentationGate;
  final GetInitialRemoteMessageFn? getInitialRemoteMessage;
  final bool Function()? shouldHandleInitialPushOpen;
  final Future<IosApnsInitialNotificationOpenDisposition> Function()?
  consumeInitialIosApnsNotificationOpen;
  final Future<void> Function()? clearDeliveredNotifications;

  /// Clears only the native iOS notification-recovery state owned by the
  /// account being erased. This is intentionally distinct from the broad
  /// delivered-notification clearing seam.
  final Future<void> Function()? clearIosNotificationRecovery;
  final Future<void> Function()? ingestStagedPushEnvelopes;
  final NotificationOpenRouteContext Function(
    NotificationRouteTarget routeTarget,
  )?
  createNotificationRouteContext;
  final Future<void> Function(NotificationOpenRouteContext context)?
  onNotificationRouteContext;
  final AccountMigrationTransferRunFn? accountMigrationRunTransfer;
  final AccountMigrationSizeGate? accountMigrationSizeGate;
  final AccountMigrationReceiverStartFn? accountMigrationStartReceiver;
  final AccountMigrationReceiverStopFn? accountMigrationStopReceiver;
  final AccountMigrationReceiverEvents? accountMigrationReceiverEvents;
  final Future<void> Function()? onAccountMigrationReceiverActivated;
  // 133: fired once the startup home surface has been pushed, so the app shell
  // can release a deferred notification route ON TOP of it (instead of racing
  // — and losing to — the home's pushReplacement).
  final VoidCallback? onStartupHomeReady;

  /// Authoritative cold-start poll for Android's durable dropped-FCM marker.
  /// Invoked only after the P2P node reports successful startup.
  final Future<void> Function()? recoverDroppedPushes;
  final Future<bool> Function()? hasPendingDroppedPushRecovery;

  /// Exact dropped-push recovery result for cold-start callers that must know
  /// whether both canonical inboxes fully converged. When recovery owns the
  /// inboxes this replaces [recoverDroppedPushes] for the exact settlement
  /// path; the legacy callback remains the fire-and-forget fallback.
  final Future<bool> Function()? recoverDroppedPushesCompletely;

  /// Optional iOS-only settlement seam. Its presence enables an exact
  /// cold-start barrier after node-start succeeds: the full direct inbox and
  /// full group startup recovery are awaited before completeness is reported.
  /// Null preserves the historical fire-and-forget startup behavior.
  /// [onIosNotificationColdStartRecoveryStarted] is awaited first so native
  /// recovery can capture its watermark before any exact inbox mutation.
  final Future<Object?> Function()? onIosNotificationColdStartRecoveryStarted;
  final Future<void> Function({
    required Object? recoveryHandle,
    required bool canonicalStateComplete,
  })?
  onIosNotificationColdStartRecoverySettled;

  /// FDC-09 §12 / CV-14 (217 §A1): once-per-cycle wake-token mint+register.
  /// Invoked EXACTLY ONCE with all active contact peerIds after a successful
  /// node start (INV-5: never per-contact / per-send). Null in tests that don't
  /// exercise it. Returns the relay ack (false = graceful degrade, NET-REL-07).
  final Future<bool> Function(List<String> contactPeerIds)?
  issueWakeTokensForContacts;

  const StartupRouter({
    super.key,
    required this.repository,
    required this.contactRepository,
    required this.contactRequestRepository,
    required this.contactRequestListener,
    required this.messageRepository,
    required this.postRepository,
    required this.mediaAttachmentRepository,
    required this.chatMessageListener,
    required this.bridge,
    required this.p2pService,
    this.transportMetrics,
    required this.mediaFileManager,
    required this.secureKeyStore,
    required this.imageProcessor,
    this.conversationTracker,
    this.audioRecorderService,
    this.reactionRepository,
    this.reactionListener,
    this.groupRepository,
    this.groupMessageRepository,
    this.groupExitDiagnosticRepository,
    this.groupInviteDeliveryAttemptRepository,
    this.groupPendingKeyRepairRepository,
    this.requestGroupKeyRepair,
    this.groupHistoryGapRepairRepository,
    this.groupReactionReplayOutboxRepository,
    this.groupPendingReactionRepository,
    this.groupMessageListener,
    this.groupMediaDownloadCoordinator,
    this.canRejoinForExitIntent,
    this.processExitIntent,
    this.groupExitIntentRecovery,
    this.groupInviteListener,
    this.waitForGroupMembershipUpdateIdle,
    this.groupConversationTracker,
    this.introductionRepository,
    this.introReviewSeenRepository,
    this.introductionListener,
    this.shareIntentService,
    this.initialShareIntentCapture,
    this.ensureRuntimeServicesReady,
    this.startP2PNodeOverride,
    this.startEarlyLocalDiscovery,
    required this.appShellController,
    required this.pendingPostTargetStore,
    required this.postsPrivacySettingsRepository,
    required this.feedClearedRepository,
    this.contactPresenceSnapshotRepository,
    this.nearbyLocationService,
    this.pushRegistrationCoordinator,
    this.contactRequestPresentationGate,
    this.getInitialRemoteMessage,
    this.shouldHandleInitialPushOpen,
    this.consumeInitialIosApnsNotificationOpen,
    this.clearDeliveredNotifications,
    this.clearIosNotificationRecovery,
    this.ingestStagedPushEnvelopes,
    this.createNotificationRouteContext,
    this.onNotificationRouteContext,
    this.accountMigrationRunTransfer,
    this.accountMigrationSizeGate,
    this.accountMigrationStartReceiver,
    this.accountMigrationStopReceiver,
    this.accountMigrationReceiverEvents,
    this.onAccountMigrationReceiverActivated,
    this.onStartupHomeReady,
    this.recoverDroppedPushes,
    this.hasPendingDroppedPushRecovery,
    this.recoverDroppedPushesCompletely,
    this.onIosNotificationColdStartRecoveryStarted,
    this.onIosNotificationColdStartRecoverySettled,
    this.issueWakeTokensForContacts,
  });

  @override
  State<StartupRouter> createState() => _StartupRouterState();
}

class _StartupRouterState extends State<StartupRouter> {
  bool _hasError = false;
  String _errorMessage = '';
  String _startupStage = startupStageCheckingIdentity;

  @override
  void initState() {
    super.initState();
    _routeBasedOnIdentity();
  }

  Future<void> _routeBasedOnIdentity() async {
    emitFlowEvent(layer: 'FL', event: 'ID_STARTUP_FLOW_BEGIN', details: {});

    try {
      _setStartupStage(startupStageCheckingIdentity);

      await widget.initialShareIntentCapture;
      final backgroundPreference = await loadBackgroundPreference(
        secureKeyStore: widget.secureKeyStore,
      );
      if (!mounted) return;
      widget.appShellController.setBackgroundPreference(backgroundPreference);

      final migrationAuthorityRepository =
          SecureKeyStoreAccountMigrationAuthorityRepository(
            secureKeyStore: widget.secureKeyStore,
          );
      var decision = await decideStartupRoute(
        identityRepo: widget.repository,
        contactRepo: widget.contactRepository,
        migrationAuthorityRepository: migrationAuthorityRepository,
      );

      if (!mounted) return;

      AccountMigrationAuthorityRecord? confirmedBlockedRecord;
      if (decision == StartupDecision.accountMigrationBlocked) {
        try {
          confirmedBlockedRecord = await migrationAuthorityRepository
              .loadAuthority();
        } catch (_) {
          confirmedBlockedRecord = null;
        }
        if (!mounted) return;

        if (confirmedBlockedRecord?.allowsNormalStartup == true) {
          emitFlowEvent(
            layer: 'FL',
            event: 'ID_STARTUP_MIGRATION_AUTHORITY_REDECIDE',
            details: {'state': confirmedBlockedRecord!.state.wireName},
          );
          decision = await decideStartupRoute(
            identityRepo: widget.repository,
            contactRepo: widget.contactRepository,
            migrationAuthorityRepository: migrationAuthorityRepository,
          );
          if (!mounted) return;
          if (decision == StartupDecision.accountMigrationBlocked) {
            // Authority changed again while re-deciding. Stay fail-safe and
            // never hand an earlier normal-start record to the erase surface.
            confirmedBlockedRecord = null;
          }
        }
      }

      // Capture locally to avoid widget reference issues after async gap
      final bridge = widget.bridge;
      final repository = widget.repository;
      final contactRepository = widget.contactRepository;
      final contactRequestRepository = widget.contactRequestRepository;
      final contactRequestListener = widget.contactRequestListener;
      final messageRepository = widget.messageRepository;
      final postRepository = widget.postRepository;
      final mediaAttachmentRepository = widget.mediaAttachmentRepository;
      final chatMessageListener = widget.chatMessageListener;
      final p2pService = widget.p2pService;
      final transportMetrics = widget.transportMetrics;

      switch (decision) {
        case StartupDecision.accountMigrationBlocked:
          emitFlowEvent(
            layer: 'FL',
            event: 'ID_STARTUP_ROUTE_MIGRATION_BLOCKED',
            details: {},
          );
          await _pushStartupReplacement(
            builder: (_) => AccountMigrationBlockedScreen(
              record: confirmedBlockedRecord,
              onEraseAccount: _eraseMigratedOutAccount,
            ),
          );
          break;

        case StartupDecision.hasIdentityWithContacts:
          _setStartupStage(startupStageOpeningFeed);
          final navigator = Navigator.of(context);
          Widget buildFeed(BuildContext _) => FeedWired(
            repository: repository,
            contactRepository: contactRepository,
            contactRequestRepository: contactRequestRepository,
            contactRequestListener: contactRequestListener,
            messageRepository: messageRepository,
            postRepository: postRepository,
            mediaAttachmentRepository: mediaAttachmentRepository,
            chatMessageListener: chatMessageListener,
            bridge: bridge,
            p2pService: p2pService,
            transportMetrics: transportMetrics,
            mediaFileManager: widget.mediaFileManager,
            secureKeyStore: widget.secureKeyStore,
            imageProcessor: widget.imageProcessor,
            conversationTracker: widget.conversationTracker,
            audioRecorderService: widget.audioRecorderService,
            reactionRepository: widget.reactionRepository,
            reactionListener: widget.reactionListener,
            groupRepository: widget.groupRepository,
            groupMessageRepository: widget.groupMessageRepository,
            groupExitDiagnosticRepository: widget.groupExitDiagnosticRepository,
            groupInviteDeliveryAttemptRepository:
                widget.groupInviteDeliveryAttemptRepository,
            groupReactionReplayOutboxRepository:
                widget.groupReactionReplayOutboxRepository,
            groupMessageListener: widget.groupMessageListener,
            groupMediaDownloadCoordinator: widget.groupMediaDownloadCoordinator,
            groupInviteListener: widget.groupInviteListener,
            waitForGroupMembershipUpdateIdle:
                widget.waitForGroupMembershipUpdateIdle,
            groupConversationTracker: widget.groupConversationTracker,
            introductionRepository: widget.introductionRepository,
            introReviewSeenRepository: widget.introReviewSeenRepository,
            introductionListener: widget.introductionListener,
            appShellController: widget.appShellController,
            pendingPostTargetStore: widget.pendingPostTargetStore,
            postsPrivacySettingsRepository:
                widget.postsPrivacySettingsRepository,
            feedClearedRepository: widget.feedClearedRepository,
            contactPresenceSnapshotRepository:
                widget.contactPresenceSnapshotRepository,
            nearbyLocationService: widget.nearbyLocationService,
            accountMigrationRunTransfer: widget.accountMigrationRunTransfer,
            accountMigrationSizeGate: widget.accountMigrationSizeGate,
          );

          final pendingIntent = widget.shareIntentService
              ?.consumePendingIntent();
          if (pendingIntent != null) {
            widget.shareIntentService?.reset();
            widget.shareIntentService?.isSettled = true;

            await _pushStartupReplacement(
              builder: (routeContext) => ShareTargetPickerWired(
                shareIntent: pendingIntent,
                identityRepo: repository,
                contactRepository: contactRepository,
                messageRepository: messageRepository,
                mediaAttachmentRepository: mediaAttachmentRepository,
                chatMessageListener: chatMessageListener,
                bridge: bridge,
                p2pService: p2pService,
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
                preSendReady: widget.ensureRuntimeServicesReady,
                onClose: (_) async {
                  await Navigator.of(routeContext).pushReplacement(
                    buildStartupReplacementRoute(builder: buildFeed),
                  );
                },
              ),
            );

            unawaited(widget.ensureRuntimeServicesReady?.call());
            unawaited(_ensureMlKemKeys());
            _startP2PInBackground();
            break;
          }

          await _ensureMlKemKeys();
          final contactCount = await contactRepository.getContactCount();
          if (!mounted) return;
          unawaited(
            refreshNearbyOnStartup(
              nearbyLocationService: widget.nearbyLocationService,
            ),
          );

          emitFlowEvent(
            layer: 'FL',
            event: 'ID_STARTUP_ROUTE_FEED',
            details: {'contactCount': contactCount},
          );

          await _pushStartupReplacement(builder: buildFeed);

          // Start P2P node in background after navigation
          _startP2PInBackground();

          settleShareIntentFlow(
            shareIntentService: widget.shareIntentService,
            navigator: navigator,
            buildRoute: _buildPendingShareRoute,
          );
          break;

        case StartupDecision.hasIdentityNoContacts:
          _setStartupStage(startupStageOpeningSetup);
          await _ensureMlKemKeys();
          unawaited(
            refreshNearbyOnStartup(
              nearbyLocationService: widget.nearbyLocationService,
            ),
          );
          emitFlowEvent(
            layer: 'FL',
            event: 'ID_STARTUP_ROUTE_MAIN_NO_CONTACTS',
            details: {},
          );
          await _navigateToFirstTime(
            repository: repository,
            contactRepository: contactRepository,
            contactRequestRepository: contactRequestRepository,
            contactRequestListener: contactRequestListener,
            messageRepository: messageRepository,
            postRepository: postRepository,
            mediaAttachmentRepository: mediaAttachmentRepository,
            chatMessageListener: chatMessageListener,
            bridge: bridge,
            p2pService: p2pService,
            mediaFileManager: widget.mediaFileManager,
            secureKeyStore: widget.secureKeyStore,
            imageProcessor: widget.imageProcessor,
            conversationTracker: widget.conversationTracker,
            audioRecorderService: widget.audioRecorderService,
            reactionRepository: widget.reactionRepository,
            reactionListener: widget.reactionListener,
            groupRepository: widget.groupRepository,
            groupMessageRepository: widget.groupMessageRepository,
            groupReactionReplayOutboxRepository:
                widget.groupReactionReplayOutboxRepository,
            groupMessageListener: widget.groupMessageListener,
            groupMediaDownloadCoordinator: widget.groupMediaDownloadCoordinator,
            groupInviteListener: widget.groupInviteListener,
            groupConversationTracker: widget.groupConversationTracker,
            introductionRepository: widget.introductionRepository,
            introReviewSeenRepository: widget.introReviewSeenRepository,
            introductionListener: widget.introductionListener,
            shareIntentService: widget.shareIntentService,
          );
          break;

        case StartupDecision.needsIdentity:
          _setStartupStage(startupStageOpeningOnboarding);
          emitFlowEvent(
            layer: 'FL',
            event: 'ID_STARTUP_ROUTE_ONBOARDING',
            details: {},
          );
          final migrationActivationRefresh =
              widget.onAccountMigrationReceiverActivated;
          final restartedStartupRouter = _buildRestartedStartupRouter();
          await _pushStartupReplacement(
            builder: (_) => _AccountMigrationOnboardingActivationOwner(
              startReceiver: widget.accountMigrationStartReceiver,
              stopReceiver: widget.accountMigrationStopReceiver,
              receiverEvents: widget.accountMigrationReceiverEvents,
              refreshAfterActivation: migrationActivationRefresh,
              restartedStartupRouter: restartedStartupRouter,
              builder: (_, retainedStartReceiver, retainedStopReceiver) =>
                  IdentityChoiceWired(
                    repository: repository,
                    callIdentityGenerate: () => callIdentityGenerate(bridge),
                    callIdentityRestore: (mnemonic) =>
                        callIdentityRestore(bridge, mnemonic),
                    callMlKemKeygen: () => callMlKemKeygen(bridge),
                    secureKeyStore: widget.secureKeyStore,
                    contactRepo: contactRepository,
                    groupRepo: widget.groupRepository,
                    backgroundPreference:
                        widget.appShellController.backgroundPreference,
                    moveFromOldPhoneBuilder: (_) =>
                        AccountMigrationJourneyWired.newPhone(
                          bridge: bridge,
                          secureKeyStore: widget.secureKeyStore,
                          startReceiver: retainedStartReceiver,
                          stopReceiver: retainedStopReceiver,
                          receiverEvents: widget.accountMigrationReceiverEvents,
                          receiverActivationOwnedByParent: true,
                          backgroundPreference:
                              widget.appShellController.backgroundPreference,
                        ),
                    onNavigateToMain: (progressContext) async {
                      Navigator.of(progressContext).pushAndRemoveUntil(
                        buildStartupReplacementRoute<void>(
                          builder: (_) => FirstTimeExperienceWired(
                            repository: repository,
                            contactRepository: contactRepository,
                            contactRequestRepository: contactRequestRepository,
                            contactRequestListener: contactRequestListener,
                            messageRepository: messageRepository,
                            postRepository: postRepository,
                            mediaAttachmentRepository:
                                mediaAttachmentRepository,
                            chatMessageListener: chatMessageListener,
                            bridge: bridge,
                            p2pService: p2pService,
                            mediaFileManager: widget.mediaFileManager,
                            secureKeyStore: widget.secureKeyStore,
                            imageProcessor: widget.imageProcessor,
                            conversationTracker: widget.conversationTracker,
                            audioRecorderService: widget.audioRecorderService,
                            reactionRepository: widget.reactionRepository,
                            reactionListener: widget.reactionListener,
                            groupRepository: widget.groupRepository,
                            groupMessageRepository:
                                widget.groupMessageRepository,
                            groupExitDiagnosticRepository:
                                widget.groupExitDiagnosticRepository,
                            groupInviteDeliveryAttemptRepository:
                                widget.groupInviteDeliveryAttemptRepository,
                            groupReactionReplayOutboxRepository:
                                widget.groupReactionReplayOutboxRepository,
                            groupMessageListener: widget.groupMessageListener,
                            groupMediaDownloadCoordinator:
                                widget.groupMediaDownloadCoordinator,
                            groupInviteListener: widget.groupInviteListener,
                            groupConversationTracker:
                                widget.groupConversationTracker,
                            introductionRepository:
                                widget.introductionRepository,
                            introReviewSeenRepository:
                                widget.introReviewSeenRepository,
                            introductionListener: widget.introductionListener,
                            shareIntentService: widget.shareIntentService,
                            appShellController: widget.appShellController,
                            pendingPostTargetStore:
                                widget.pendingPostTargetStore,
                            postsPrivacySettingsRepository:
                                widget.postsPrivacySettingsRepository,
                            feedClearedRepository: widget.feedClearedRepository,
                            contactPresenceSnapshotRepository:
                                widget.contactPresenceSnapshotRepository,
                            nearbyLocationService: widget.nearbyLocationService,
                            transportMetrics: widget.transportMetrics,
                            accountMigrationRunTransfer:
                                widget.accountMigrationRunTransfer,
                            accountMigrationSizeGate:
                                widget.accountMigrationSizeGate,
                          ),
                        ),
                        (_) => false,
                      );

                      StartupTiming.instance.mark('route_pushed');

                      // Start P2P node in background after identity creation
                      _startP2PInBackground();
                    },
                  ),
            ),
          );
          break;
      }
    } catch (e) {
      if (!mounted) return;

      emitFlowEvent(
        layer: 'FL',
        event: 'ID_STARTUP_ROUTE_ERROR',
        details: {'error': e.toString()},
      );

      setState(() {
        _hasError = true;
        _errorMessage = e.toString();
      });
    }
  }

  /// Start the P2P node in the background.
  ///
  /// This is called after navigating to the main screen, so failures
  /// don't block the user experience.
  Future<void> _startP2PInBackground() async {
    if (StartupConfig.deferredStartupMode) {
      // Defer P2P startup to next frame to avoid contending with UI rendering
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _doStartP2P();
      });
    } else {
      _doStartP2P();
    }
  }

  Future<void> _doStartP2P() async {
    final ensureRuntimeServicesReady = widget.ensureRuntimeServicesReady;
    if (ensureRuntimeServicesReady != null) {
      await ensureRuntimeServicesReady();
    }

    StartupTiming.instance.mark('p2p_startup_begin');
    emitFlowEvent(layer: 'FL', event: 'P2P_STARTUP_BEGIN', details: {});

    final startP2PNodeOverride = widget.startP2PNodeOverride;
    final result = startP2PNodeOverride != null
        ? await startP2PNodeOverride()
        : await startP2PNode(
            identityRepo: widget.repository,
            p2pService: widget.p2pService,
            accountMigrationNetworkGate: AccountMigrationRuntimeNetworkGate(
              authorityRepository:
                  SecureKeyStoreAccountMigrationAuthorityRepository(
                    secureKeyStore: widget.secureKeyStore,
                  ),
            ).allowsAccountNetworkSideEffects,
            // 360: an ordinary primary resolves to
            // `LinkedInstallationDisposition.primary`, so this reads the two
            // secure keys and then takes the byte-for-byte incumbent path. A
            // linked secondary starts its own transport; a half-written or
            // crossed credential refuses instead of falling back to the
            // account transport.
            linkedAuthority: await LinkedInstallationAuthority(
              secureKeyStore: widget.secureKeyStore,
            ).load(),
          );

    emitFlowEvent(
      layer: 'FL',
      event: 'P2P_STARTUP_RESULT',
      details: {'result': result.name},
    );

    if (result == StartNodeResult.success) {
      StartupTiming.instance.mark('p2p_startup_complete');
      StartupTiming.instance.printSummary();
      // FDC-07: trigger early LAN mDNS discovery on the cold-start branch — AFTER
      // the plan-164 ensureRuntimeServicesReady gate (above; node-start ordering
      // is NOT reordered) and BEFORE the group-rejoin/drain block below.
      // Idempotent with startNode's own early seam; opportunistic (never blocks).
      unawaited(widget.startEarlyLocalDiscovery?.call());
      unawaited(
        refreshNearbyOnStartup(
          nearbyLocationService: widget.nearbyLocationService,
        ),
      );
      final settleIosColdStartRecovery =
          widget.onIosNotificationColdStartRecoverySettled;
      if (settleIosColdStartRecovery == null) {
        unawaited(_handleInitialPushOpen().then<void>((_) {}));
      }
      final pushRegistrationCoordinator = widget.pushRegistrationCoordinator;
      if (pushRegistrationCoordinator != null) {
        unawaited(pushRegistrationCoordinator.ensureStarted());
      }

      // FDC-09 §12 / CV-14 (217 §A1): mint+register this node's wake-token SET
      // ONCE per node-start with all active contacts (whole-cycle; the relay set
      // is not durable, so re-register after a bounce/restart). Fire-and-forget,
      // total (never throws — the callback wrapper degrades to false). Coalesced
      // stream re-issue (main.dart) + the read-only per-send resolver keep this
      // the ONLY mint/register trigger (INV-5).
      final issueWakeTokens = widget.issueWakeTokensForContacts;
      if (issueWakeTokens != null) {
        unawaited(() async {
          final contacts = await widget.contactRepository.getActiveContacts();
          // Exclude BLOCKED contacts (getActiveContacts filters archived only) —
          // a blocked peer must NOT keep a valid registered wake-token, and
          // reconcile-down prunes any it already minted. Mirrors the retry
          // distribution path's `!c.isBlocked`.
          await issueWakeTokens(
            contacts
                .where((c) => !c.isBlocked)
                .map((c) => c.peerId)
                .toList(growable: false),
          );
        }());
      }

      var droppedPushRecoveryOwnsInbox = false;
      final hasPendingDroppedPushRecovery =
          widget.hasPendingDroppedPushRecovery;
      if (hasPendingDroppedPushRecovery != null) {
        try {
          droppedPushRecoveryOwnsInbox = await hasPendingDroppedPushRecovery();
        } catch (error) {
          droppedPushRecoveryOwnsInbox = true;
          emitFlowEvent(
            layer: 'FL',
            event: 'DROPPED_PUSH_RECOVERY_COLD_OWNERSHIP_ERROR',
            details: {'error': error.runtimeType.toString()},
          );
        }
      }

      var iosColdStartRecoveryStarted = settleIosColdStartRecovery == null;
      Object? iosColdStartRecoveryHandle;
      if (settleIosColdStartRecovery != null) {
        final startIosColdStartRecovery =
            widget.onIosNotificationColdStartRecoveryStarted;
        if (startIosColdStartRecovery == null) {
          emitFlowEvent(
            layer: 'FL',
            event: 'IOS_NOTIFICATION_COLD_START_RECOVERY_BEGIN_ERROR',
            details: {'error': 'missing_begin_boundary'},
          );
        }
        try {
          iosColdStartRecoveryHandle = await startIosColdStartRecovery?.call();
          iosColdStartRecoveryStarted =
              startIosColdStartRecovery != null &&
              iosColdStartRecoveryHandle != null;
        } catch (error) {
          iosColdStartRecoveryStarted = false;
          emitFlowEvent(
            layer: 'FL',
            event: 'IOS_NOTIFICATION_COLD_START_RECOVERY_BEGIN_ERROR',
            details: {'error': error.runtimeType.toString()},
          );
        }
      }

      var initialIosApnsOpenComplete = true;
      var initialPushOpenComplete = true;
      if (settleIosColdStartRecovery != null) {
        final initialIosApnsOpen =
            await _consumeInitialIosApnsNotificationOpen();
        initialIosApnsOpenComplete =
            initialIosApnsOpen !=
            IosApnsInitialNotificationOpenDisposition.failed;
        if (initialIosApnsOpen !=
            IosApnsInitialNotificationOpenDisposition.routed) {
          // The native AppDelegate path is authoritative on iOS. Consult FCM
          // only when native had no pending open (or its bridge failed), so one
          // cold tap cannot be routed twice by both integrations.
          initialPushOpenComplete = await _handleInitialPushOpen();
        }
      }

      // Now that the Go node is running (pubsub initialized), rejoin group
      // topics and drain offline inboxes. Fire-and-forget — errors are logged
      // inside each function and don't block startup.
      final groupRepo = widget.groupRepository;
      final groupMsgRepo = widget.groupMessageRepository;
      Future<bool>? startupGroupRecovery;
      if (groupRepo != null) {
        startupGroupRecovery = runWithGroupRecoveryGate(() async {
          var canonicalGroupInboxComplete = false;
          IdentityModel? identity;
          try {
            identity = await widget.repository.loadIdentity();
            await rejoinGroupTopics(
              bridge: widget.bridge,
              groupRepo: groupRepo,
              canRejoinForExitIntent: widget.canRejoinForExitIntent,
              processExitIntent: widget.processExitIntent,
            );
            // 123 S1 — after rejoin, reconcile any missed TERMINAL dissolve so a
            // group dissolved while we were offline converges (and is left)
            // instead of staying live. Runs AFTER rejoin so active groups
            // re-subscribe immediately — the cursor-independent inbox scan must
            // not delay live-message reception (see IR-018).
            final groupMsgListener = widget.groupMessageListener;
            if (groupMsgListener != null) {
              await reconcileMissedGroupDissolves(
                bridge: widget.bridge,
                groupRepo: groupRepo,
                groupMessageListener: groupMsgListener,
                selfPeerId: identity?.peerId,
              );
            }
            if (groupMsgRepo != null && !droppedPushRecoveryOwnsInbox) {
              final drainResult = await drainGroupOfflineInbox(
                bridge: widget.bridge,
                groupRepo: groupRepo,
                msgRepo: groupMsgRepo,
                groupMessageListener: widget.groupMessageListener,
                mediaAttachmentRepo: widget.mediaAttachmentRepository,
                reactionRepo: widget.reactionRepository,
                pendingReactionRepo: widget.groupPendingReactionRepository,
                pendingKeyRepairRepo: widget.groupPendingKeyRepairRepository,
                historyGapRepairRepo: widget.groupHistoryGapRepairRepository,
                requestGroupKeyRepair:
                    widget.requestGroupKeyRepair ?? emitGroupKeyRepairRequest,
                selfPeerId: identity?.peerId,
              );
              canonicalGroupInboxComplete =
                  drainResult.isSuccessful && !drainResult.hasMorePages;
            } else if (droppedPushRecoveryOwnsInbox) {
              emitFlowEvent(
                layer: 'FL',
                event: 'GROUP_STARTUP_INBOX_DRAIN_REPLACED',
                details: {'owner': 'dropped_push_recovery'},
              );
            }
          } catch (error) {
            emitFlowEvent(
              layer: 'FL',
              event: 'GROUP_STARTUP_NETWORK_RECOVERY_ERROR',
              details: {'error': error.toString()},
            );
            return false;
          } finally {
            // PB264-18: a fresh launch cannot depend on an initial resumed
            // callback. Recovery is independent of discovery/rejoin/drain
            // success so local terminal/cleanup phases cannot be stranded.
            await _recoverGroupExitIntentsAtStartup();
          }
          // R1 (B1b): if this is a freshly-restored device, announce its new
          // per-device identity to its groups so a sibling/admin can admit it
          // and re-distribute the current key. One-shot (marker-gated) and
          // inert unless kMultiDeviceSyncEnabled is on. Never blocks startup.
          await maybeAnnounceRestoredDeviceOnStartup(
            secureKeyStore: widget.secureKeyStore,
            bridge: widget.bridge,
            groupRepo: groupRepo,
            identity: identity,
            transportPeerId: widget.p2pService.currentState.peerId,
          );
          return canonicalGroupInboxComplete;
        });
        unawaited(startupGroupRecovery);
      } else {
        unawaited(_recoverGroupExitIntentsAtStartup());
      }

      final recoverDroppedPushes = widget.recoverDroppedPushes;
      final shouldRecoverDroppedPushes =
          recoverDroppedPushes != null &&
          (hasPendingDroppedPushRecovery == null ||
              droppedPushRecoveryOwnsInbox);
      if (settleIosColdStartRecovery != null) {
        unawaited(
          _settleIosNotificationColdStartRecovery(
            startupGroupRecovery: startupGroupRecovery,
            groupRepositoriesAbsent: groupRepo == null && groupMsgRepo == null,
            droppedPushRecoveryOwnsInbox: droppedPushRecoveryOwnsInbox,
            shouldRecoverDroppedPushes: shouldRecoverDroppedPushes,
            recoveryHandle: iosColdStartRecoveryHandle,
            recoveryStartSucceeded:
                iosColdStartRecoveryStarted &&
                initialIosApnsOpenComplete &&
                initialPushOpenComplete,
          ),
        );
      } else if (shouldRecoverDroppedPushes) {
        unawaited(() async {
          try {
            final groupRecovery = startupGroupRecovery;
            if (groupRecovery != null) {
              await groupRecovery;
            }
            await recoverDroppedPushes();
          } catch (error) {
            emitFlowEvent(
              layer: 'FL',
              event: 'DROPPED_PUSH_RECOVERY_COLD_START_ERROR',
              details: {'error': error.runtimeType.toString()},
            );
          }
        }());
      }
    } else {
      // Node startup can fail while cleanup_pending work is entirely local.
      // Queue one isolated pass even though no network prerequisite is usable.
      unawaited(_recoverGroupExitIntentsAtStartup());
      if (widget.onIosNotificationColdStartRecoverySettled != null) {
        // Production keeps AppDelegate warm forwarding disabled until the
        // initial APNs response is captured inside a native recovery scope.
        // A failed node start cannot leave that launch response stranded:
        // release it through the same boundary, but never claim canonical
        // completeness or run network inbox drains.
        unawaited(_releaseIosNotificationOpenAfterFailedNodeStart());
      }
    }
  }

  Future<void> _releaseIosNotificationOpenAfterFailedNodeStart() async {
    Object? recoveryHandle;
    final beginRecovery = widget.onIosNotificationColdStartRecoveryStarted;
    if (beginRecovery == null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'IOS_NOTIFICATION_COLD_START_RECOVERY_BEGIN_ERROR',
        details: {'error': 'missing_begin_boundary'},
      );
    } else {
      try {
        recoveryHandle = await beginRecovery();
      } catch (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'IOS_NOTIFICATION_COLD_START_RECOVERY_BEGIN_ERROR',
          details: {'error': error.runtimeType.toString()},
        );
      }
    }

    try {
      final initialIosApnsOpen = await _consumeInitialIosApnsNotificationOpen();
      if (initialIosApnsOpen !=
          IosApnsInitialNotificationOpenDisposition.routed) {
        await _handleInitialPushOpen();
      }
    } finally {
      final settle = widget.onIosNotificationColdStartRecoverySettled;
      if (settle != null) {
        try {
          await settle(
            recoveryHandle: recoveryHandle,
            canonicalStateComplete: false,
          );
        } catch (error) {
          emitFlowEvent(
            layer: 'FL',
            event: 'IOS_NOTIFICATION_COLD_START_SETTLEMENT_ERROR',
            details: {'error': error.runtimeType.toString()},
          );
        }
      }
    }
  }

  Future<void> _settleIosNotificationColdStartRecovery({
    required Future<bool>? startupGroupRecovery,
    required bool groupRepositoriesAbsent,
    required bool droppedPushRecoveryOwnsInbox,
    required bool shouldRecoverDroppedPushes,
    required Object? recoveryHandle,
    required bool recoveryStartSucceeded,
  }) async {
    var canonicalStateComplete = false;
    try {
      if (droppedPushRecoveryOwnsInbox) {
        // Preserve the existing ordering: group rejoin/recovery establishes its
        // startup state before the dropped-push coordinator takes ownership of
        // both inboxes. Its inbox result is deliberately ignored here because
        // the dropped coordinator is the authoritative full-drain boundary.
        final groupRecovery = startupGroupRecovery;
        if (groupRecovery != null) {
          await groupRecovery;
        }

        final recoverCompletely = widget.recoverDroppedPushesCompletely;
        if (recoverCompletely != null) {
          canonicalStateComplete = await recoverCompletely();
        } else {
          // Retain the legacy recovery side effect but never upgrade its void
          // result to an exact completeness claim.
          final recover = widget.recoverDroppedPushes;
          if (shouldRecoverDroppedPushes && recover != null) {
            await recover();
          }
        }
      } else {
        final p2pService = widget.p2pService;
        final directInboxRecovery = p2pService is P2PFullInboxDrain
            ? (p2pService as P2PFullInboxDrain).drainOfflineInboxFully().then(
                (outcome) => outcome.isSuccessful && !outcome.hasMore,
              )
            : Future<bool>.value(false);
        final groupInboxRecovery =
            startupGroupRecovery ?? Future<bool>.value(groupRepositoriesAbsent);
        final results = await Future.wait<bool>([
          directInboxRecovery,
          groupInboxRecovery,
        ]);
        canonicalStateComplete = results.every((result) => result);

        // A legacy dropped-recovery callback without an ownership poll may
        // still mutate both inboxes. Preserve that behavior, but its void
        // result cannot support a complete reconciliation claim.
        final recover = widget.recoverDroppedPushes;
        if (shouldRecoverDroppedPushes && recover != null) {
          await recover();
          canonicalStateComplete = false;
        }
      }
    } catch (error) {
      canonicalStateComplete = false;
      emitFlowEvent(
        layer: 'FL',
        event: 'IOS_NOTIFICATION_COLD_START_RECOVERY_ERROR',
        details: {'error': error.runtimeType.toString()},
      );
    }

    canonicalStateComplete = recoveryStartSucceeded && canonicalStateComplete;

    final settle = widget.onIosNotificationColdStartRecoverySettled;
    if (settle == null) return;
    try {
      await settle(
        recoveryHandle: recoveryHandle,
        canonicalStateComplete: canonicalStateComplete,
      );
    } catch (error) {
      // This runs in a detached startup task. Keep the reporting boundary
      // total so native-recovery failures cannot become unhandled UI errors.
      emitFlowEvent(
        layer: 'FL',
        event: 'IOS_NOTIFICATION_COLD_START_SETTLEMENT_ERROR',
        details: {'error': error.runtimeType.toString()},
      );
    }
  }

  Future<void> _recoverGroupExitIntentsAtStartup() async {
    final recover = widget.groupExitIntentRecovery;
    if (recover == null) return;
    try {
      await recover();
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_EXIT_INTENT_STARTUP_RECOVERY_ERROR',
        details: {'error': error.toString()},
      );
    }
  }

  Future<void> _eraseMigratedOutAccount() async {
    try {
      await widget.clearIosNotificationRecovery?.call();
    } catch (error) {
      // An unsupported future native sidecar must remain byte-preserved, but
      // it cannot hold the authoritative secure-account erase hostage.
      emitFlowEvent(
        layer: 'FL',
        event: 'ACCOUNT_MIGRATION_IOS_NOTIFICATION_RECOVERY_CLEAR_FAILED',
        details: {'errorType': error.runtimeType.toString()},
      );
    }
    final staging = MigrationSecureStorageStaging(
      primaryStore: widget.secureKeyStore,
      sharedStore: widget.secureKeyStore,
    );
    await MigrationSecureStorageCleanup(staging: staging).eraseAccount(
      registryKeys: MigrationSecureStorageRegistry.resolve(),
      explicitLocalReset: true,
    );
    await SecureKeyStoreAccountMigrationAuthorityRepository(
      secureKeyStore: widget.secureKeyStore,
    ).clearAuthority();
  }

  Future<bool> _handleInitialPushOpen() async {
    final shouldHandleInitialPushOpen = widget.shouldHandleInitialPushOpen;
    if (shouldHandleInitialPushOpen != null) {
      if (!shouldHandleInitialPushOpen()) {
        return true;
      }
    } else {
      if (kIsWeb ||
          Platform.isLinux ||
          Platform.isWindows ||
          Platform.isMacOS) {
        return true;
      }

      if (Firebase.apps.isEmpty) return true;
    }

    try {
      await handleInitialRemoteMessage(
        getInitialMessage:
            widget.getInitialRemoteMessage ??
            FirebaseMessaging.instance.getInitialMessage,
        onMessageOpened: (message) async {
          emitFlowEvent(
            layer: 'FL',
            event: 'PUSH_INITIAL_MESSAGE_OPENED',
            details: {
              'messageId': message.messageId,
              'dataKeys': message.data.keys.toList(),
            },
          );
          final routeTarget = NotificationRouteTarget.fromRemoteMessageData(
            message.data,
          );
          NotificationOpenRouteContext? preparedContext;
          await _withContactRequestPresentationSuppressed(
            routeTarget: routeTarget,
            action: () => routeRemoteNotificationOpen(
              data: message.data,
              onBeforeRouteTarget: (resolvedRouteTarget) async {
                final createContext = widget.createNotificationRouteContext;
                if (createContext == null) {
                  throw StateError(
                    'Initial notification route context factory is missing.',
                  );
                }
                // The shared app-root coordinator assigns the ordinal here,
                // before route preparation can yield. Android dismisses the
                // selected remote card; unrelated cards must remain delivered.
                preparedContext = createContext(resolvedRouteTarget);
                await _prepareNotificationRouteTarget(resolvedRouteTarget);
              },
              onRouteTarget: (resolvedRouteTarget) async {
                final context = preparedContext;
                if (context == null ||
                    !identical(context.routeTarget, resolvedRouteTarget)) {
                  throw StateError(
                    'Initial notification route context was not prepared.',
                  );
                }
                if (widget.onNotificationRouteContext == null) {
                  return;
                }
                await widget.onNotificationRouteContext!(context);
              },
              onMissingRouteTarget: widget.p2pService.drainOfflineInbox,
            ),
          );
        },
      );
      return true;
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'PUSH_INITIAL_MESSAGE_ERROR',
        details: {'error': e.toString()},
      );
      return false;
    }
  }

  Future<IosApnsInitialNotificationOpenDisposition>
  _consumeInitialIosApnsNotificationOpen() async {
    final consume = widget.consumeInitialIosApnsNotificationOpen;
    if (consume == null) {
      return IosApnsInitialNotificationOpenDisposition.empty;
    }
    try {
      return await consume();
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'IOS_APNS_INITIAL_NOTIFICATION_OPEN_ERROR',
        details: {'error': error.runtimeType.toString()},
      );
      return IosApnsInitialNotificationOpenDisposition.failed;
    }
  }

  Future<void> _withContactRequestPresentationSuppressed({
    required NotificationRouteTarget? routeTarget,
    required Future<void> Function() action,
  }) async {
    final gate = widget.contactRequestPresentationGate;
    final peerId =
        routeTarget?.kind == NotificationRouteTargetKind.contactRequest
        ? routeTarget?.peerId
        : null;
    if (gate != null && peerId != null) {
      gate.suppress(peerId);
    }
    try {
      await action();
    } finally {
      if (gate != null && peerId != null) {
        gate.release(peerId);
      }
    }
  }

  /// Ensure the current identity has ML-KEM keys.
  ///
  /// Existing users created before ML-KEM support won't have keys.
  /// This generates and saves them. Non-fatal: if it fails, user
  /// continues with plaintext messaging.
  Future<void> _ensureMlKemKeys() async {
    try {
      final ensureRuntimeServicesReady = widget.ensureRuntimeServicesReady;
      if (ensureRuntimeServicesReady != null) {
        await ensureRuntimeServicesReady();
      }

      final identity = await widget.repository.loadIdentity();
      final hasMlKemPublicKey =
          identity?.mlKemPublicKey?.trim().isNotEmpty == true;
      final hasMlKemSecretKey =
          identity?.mlKemSecretKey?.trim().isNotEmpty == true;
      if (identity == null || (hasMlKemPublicKey && hasMlKemSecretKey)) {
        return;
      }

      emitFlowEvent(
        layer: 'FL',
        event: 'MLKEM_MIGRATION_START',
        details: {
          'kemPublicPresent': hasMlKemPublicKey,
          'kemDecapPresent': hasMlKemSecretKey,
        },
      );

      final mlKemResponse = await callMlKemKeygen(widget.bridge);
      if (mlKemResponse['ok'] != true) {
        emitFlowEvent(
          layer: 'FL',
          event: 'MLKEM_MIGRATION_ERROR',
          details: {'errorCode': mlKemResponse['errorCode']},
        );
        return;
      }

      final enriched = IdentityModel(
        peerId: identity.peerId,
        publicKey: identity.publicKey,
        privateKey: identity.privateKey,
        mnemonic12: identity.mnemonic12,
        mlKemPublicKey: mlKemResponse['publicKey'] as String,
        mlKemSecretKey: mlKemResponse['secretKey'] as String,
        username: identity.username,
        avatarBlob: identity.avatarBlob,
        avatarVersion: identity.avatarVersion,
        createdAt: identity.createdAt,
        updatedAt: identity.updatedAt,
      );

      await widget.repository.saveIdentity(enriched);

      emitFlowEvent(layer: 'FL', event: 'MLKEM_MIGRATION_OK', details: {});
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'MLKEM_MIGRATION_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _retry() async {
    setState(() {
      _hasError = false;
      _errorMessage = '';
      _startupStage = startupStageCheckingIdentity;
    });
    await _routeBasedOnIdentity();
  }

  Future<void> _navigateToFirstTime({
    required IdentityRepository repository,
    required ContactRepository contactRepository,
    required ContactRequestRepository contactRequestRepository,
    required ContactRequestListener contactRequestListener,
    required MessageRepository messageRepository,
    required PostRepository postRepository,
    required MediaAttachmentRepository mediaAttachmentRepository,
    required ChatMessageListener chatMessageListener,
    required Bridge bridge,
    required P2PService p2pService,
    required MediaFileManager mediaFileManager,
    required SecureKeyStore secureKeyStore,
    required ImageProcessor imageProcessor,
    ActiveConversationTracker? conversationTracker,
    AudioRecorderService? audioRecorderService,
    ReactionRepository? reactionRepository,
    ReactionListener? reactionListener,
    GroupRepository? groupRepository,
    GroupMessageRepository? groupMessageRepository,
    GroupReactionReplayOutboxRepository? groupReactionReplayOutboxRepository,
    GroupMessageListener? groupMessageListener,
    GroupMediaDownloadCoordinator? groupMediaDownloadCoordinator,
    GroupInviteListener? groupInviteListener,
    ActiveConversationTracker? groupConversationTracker,
    IntroductionRepository? introductionRepository,
    IntroReviewSeenRepository? introReviewSeenRepository,
    IntroductionListener? introductionListener,
    ShareIntentService? shareIntentService,
  }) async {
    await _pushStartupReplacement(
      builder: (_) => FirstTimeExperienceWired(
        repository: repository,
        contactRepository: contactRepository,
        contactRequestRepository: contactRequestRepository,
        contactRequestListener: contactRequestListener,
        messageRepository: messageRepository,
        postRepository: postRepository,
        mediaAttachmentRepository: mediaAttachmentRepository,
        chatMessageListener: chatMessageListener,
        bridge: bridge,
        p2pService: p2pService,
        mediaFileManager: mediaFileManager,
        secureKeyStore: secureKeyStore,
        imageProcessor: imageProcessor,
        conversationTracker: conversationTracker,
        audioRecorderService: audioRecorderService,
        reactionRepository: reactionRepository,
        reactionListener: reactionListener,
        groupRepository: groupRepository,
        groupMessageRepository: groupMessageRepository,
        groupExitDiagnosticRepository: widget.groupExitDiagnosticRepository,
        groupInviteDeliveryAttemptRepository:
            widget.groupInviteDeliveryAttemptRepository,
        groupReactionReplayOutboxRepository:
            groupReactionReplayOutboxRepository,
        groupMessageListener: groupMessageListener,
        groupMediaDownloadCoordinator: groupMediaDownloadCoordinator,
        groupInviteListener: groupInviteListener,
        groupConversationTracker: groupConversationTracker,
        introductionRepository: introductionRepository,
        introReviewSeenRepository: introReviewSeenRepository,
        introductionListener: introductionListener,
        shareIntentService: shareIntentService,
        appShellController: widget.appShellController,
        pendingPostTargetStore: widget.pendingPostTargetStore,
        postsPrivacySettingsRepository: widget.postsPrivacySettingsRepository,
        feedClearedRepository: widget.feedClearedRepository,
        contactPresenceSnapshotRepository:
            widget.contactPresenceSnapshotRepository,
        nearbyLocationService: widget.nearbyLocationService,
        transportMetrics: widget.transportMetrics,
        accountMigrationRunTransfer: widget.accountMigrationRunTransfer,
        accountMigrationSizeGate: widget.accountMigrationSizeGate,
      ),
    );

    // Start P2P in background after navigation
    _startP2PInBackground();
  }

  void _setStartupStage(String stage) {
    if (!mounted || _startupStage == stage) return;
    setState(() => _startupStage = stage);
  }

  Future<void> _prepareNotificationRouteTarget(
    NotificationRouteTarget routeTarget,
  ) async {
    final identity = await widget.repository.loadIdentity();
    await prepareNotificationRouteTarget(
      routeTarget: routeTarget,
      drainOfflineInbox: widget.p2pService.drainOfflineInbox,
      bridge: widget.bridge,
      groupRepository: widget.groupRepository,
      groupMessageRepository: widget.groupMessageRepository,
      pendingKeyRepairRepository: widget.groupPendingKeyRepairRepository,
      historyGapRepairRepository: widget.groupHistoryGapRepairRepository,
      groupMessageListener: widget.groupMessageListener,
      mediaAttachmentRepository: widget.mediaAttachmentRepository,
      reactionRepository: widget.reactionRepository,
      groupPendingReactionRepository: widget.groupPendingReactionRepository,
      selfPeerId: identity?.peerId,
      ingestStagedPushEnvelopes: widget.ingestStagedPushEnvelopes,
    );
  }

  Route<void> _buildPendingShareRoute(ShareIntent intent) {
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
      preSendReady: widget.ensureRuntimeServicesReady,
    );
  }

  Future<void> _pushStartupReplacement({required WidgetBuilder builder}) async {
    if (!mounted) return;

    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    Navigator.of(
      context,
    ).pushReplacement(buildStartupReplacementRoute(builder: builder));
    StartupTiming.instance.mark('route_pushed');
    // 133: the home surface now owns the top of the stack — let the app shell
    // release any deferred notification route on top of it.
    widget.onStartupHomeReady?.call();
  }

  StartupRouter _buildRestartedStartupRouter() {
    return StartupRouter(
      repository: widget.repository,
      contactRepository: widget.contactRepository,
      contactRequestRepository: widget.contactRequestRepository,
      contactRequestListener: widget.contactRequestListener,
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
      requestGroupKeyRepair: widget.requestGroupKeyRepair,
      groupHistoryGapRepairRepository: widget.groupHistoryGapRepairRepository,
      groupReactionReplayOutboxRepository:
          widget.groupReactionReplayOutboxRepository,
      groupPendingReactionRepository: widget.groupPendingReactionRepository,
      groupMessageListener: widget.groupMessageListener,
      canRejoinForExitIntent: widget.canRejoinForExitIntent,
      processExitIntent: widget.processExitIntent,
      groupExitIntentRecovery: widget.groupExitIntentRecovery,
      groupInviteListener: widget.groupInviteListener,
      waitForGroupMembershipUpdateIdle: widget.waitForGroupMembershipUpdateIdle,
      groupConversationTracker: widget.groupConversationTracker,
      introductionRepository: widget.introductionRepository,
      introReviewSeenRepository: widget.introReviewSeenRepository,
      introductionListener: widget.introductionListener,
      shareIntentService: widget.shareIntentService,
      initialShareIntentCapture: widget.initialShareIntentCapture,
      ensureRuntimeServicesReady: widget.ensureRuntimeServicesReady,
      startP2PNodeOverride: widget.startP2PNodeOverride,
      startEarlyLocalDiscovery: widget.startEarlyLocalDiscovery,
      appShellController: widget.appShellController,
      pendingPostTargetStore: widget.pendingPostTargetStore,
      postsPrivacySettingsRepository: widget.postsPrivacySettingsRepository,
      feedClearedRepository: widget.feedClearedRepository,
      contactPresenceSnapshotRepository:
          widget.contactPresenceSnapshotRepository,
      nearbyLocationService: widget.nearbyLocationService,
      pushRegistrationCoordinator: widget.pushRegistrationCoordinator,
      contactRequestPresentationGate: widget.contactRequestPresentationGate,
      getInitialRemoteMessage: widget.getInitialRemoteMessage,
      shouldHandleInitialPushOpen: widget.shouldHandleInitialPushOpen,
      consumeInitialIosApnsNotificationOpen:
          widget.consumeInitialIosApnsNotificationOpen,
      clearDeliveredNotifications: widget.clearDeliveredNotifications,
      clearIosNotificationRecovery: widget.clearIosNotificationRecovery,
      ingestStagedPushEnvelopes: widget.ingestStagedPushEnvelopes,
      createNotificationRouteContext: widget.createNotificationRouteContext,
      onNotificationRouteContext: widget.onNotificationRouteContext,
      accountMigrationRunTransfer: widget.accountMigrationRunTransfer,
      accountMigrationSizeGate: widget.accountMigrationSizeGate,
      accountMigrationStartReceiver: widget.accountMigrationStartReceiver,
      accountMigrationStopReceiver: widget.accountMigrationStopReceiver,
      accountMigrationReceiverEvents: widget.accountMigrationReceiverEvents,
      onAccountMigrationReceiverActivated:
          widget.onAccountMigrationReceiverActivated,
      issueWakeTokensForContacts: widget.issueWakeTokensForContacts,
      recoverDroppedPushes: widget.recoverDroppedPushes,
      hasPendingDroppedPushRecovery: widget.hasPendingDroppedPushRecovery,
      recoverDroppedPushesCompletely: widget.recoverDroppedPushesCompletely,
      onIosNotificationColdStartRecoveryStarted:
          widget.onIosNotificationColdStartRecoveryStarted,
      onIosNotificationColdStartRecoverySettled:
          widget.onIosNotificationColdStartRecoverySettled,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 24),
                Text(
                  AppLocalizations.of(context)?.startup_failed_title ??
                      'Failed to initialize',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _errorMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _retry,
                  child: Text(
                    AppLocalizations.of(context)?.btn_retry ?? 'Retry',
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return StartupLoadingGate(stage: _startupStage);
  }
}
