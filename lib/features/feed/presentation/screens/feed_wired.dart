import 'dart:async';
import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/debug/transport_metrics.dart';
import 'package:flutter_app/core/media/audio_recorder_service.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/pending_composer_media.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/text_sanitizer.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_transfer_flow.dart';
import 'package:flutter_app/features/account_migration/application/migration_account_size_estimator.dart';
import 'package:flutter_app/features/settings/application/image_quality_preference_use_cases.dart';
import 'package:flutter_app/features/settings/application/background_preference_use_cases.dart';
import 'package:flutter_app/features/settings/domain/models/image_quality_preference.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contact_request/application/accept_and_reciprocate_use_case.dart';
import 'package:flutter_app/features/contact_request/application/send_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/application/accept_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contact_request/application/decline_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/contact_request/domain/repositories/contact_request_repository.dart';
import 'package:flutter_app/features/contact_request/presentation/widgets/contact_request_dialog.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/delete_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/drain_direct_inbox_custody_outbox_use_case.dart';
import 'package:flutter_app/features/conversation/application/load_reactions_use_case.dart';
import 'package:flutter_app/features/conversation/application/reaction_listener.dart';
import 'package:flutter_app/features/conversation/application/mark_conversation_read_use_case.dart';
import 'package:flutter_app/features/conversation/application/retry_failed_messages_use_case.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_change.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/conversation/presentation/navigation/conversation_route_transition.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_wired.dart';
import 'package:flutter_app/features/conversation/presentation/screens/direct_conversation_route_authority.dart';
import 'package:flutter_app/features/feed/application/feed_reaction_store.dart';
import 'package:flutter_app/features/feed/application/feed_pending_projection.dart';
import 'package:flutter_app/features/feed/application/feed_store.dart';
import 'package:flutter_app/features/feed/data/feed_cleared_repository.dart';
import 'package:flutter_app/features/feed/application/group_feed_media_verification.dart';
import 'package:flutter_app/features/feed/application/load_contact_feed_snapshot_use_case.dart';
import 'package:flutter_app/features/feed/application/load_feed_use_case.dart';
import 'package:flutter_app/features/feed/application/load_group_feed_snapshot_use_case.dart';
import 'package:flutter_app/features/feed/application/app_shell_controller.dart';
import 'package:flutter_app/features/feed/domain/models/app_shell_tab.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/domain/models/feed_route_changes.dart';
import 'package:flutter_app/features/feed/domain/models/feed_session_reply.dart';
import 'package:flutter_app/features/feed/domain/models/session_reply.dart';
import 'package:flutter_app/features/feed/domain/utils/format_message_time.dart';
import 'package:flutter_app/features/feed/domain/utils/group_group_messages_into_threads.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/retry_incomplete_group_downloads_use_case.dart';
import 'package:flutter_app/features/groups/application/group_invite_listener.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_exit_diagnostic_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_reaction_replay_outbox_repository.dart';
import 'package:flutter_app/features/groups/domain/models/pending_group_invite.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/introduction/domain/repositories/introduction_repository.dart';
import 'package:flutter_app/features/introduction/application/introduction_listener.dart';
import 'package:flutter_app/features/introduction/application/expire_old_introductions_use_case.dart';
import 'package:flutter_app/features/introduction/application/load_introductions_use_case.dart';
import 'package:flutter_app/features/introduction/application/unseen_review_count.dart';
import 'package:flutter_app/features/introduction/domain/repositories/intro_review_seen_repository.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_wired.dart';
import 'package:flutter_app/features/orbit/domain/repositories/orbit_call_activity_source.dart';
import 'package:flutter_app/features/orbit/presentation/screens/orbit_wired.dart';
import 'package:flutter_app/features/posts/application/nearby_location_service.dart';
import 'package:flutter_app/features/posts/application/pending_post_target_store.dart';
import 'package:flutter_app/features/posts/domain/repositories/contact_presence_snapshot_repository.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';
import 'package:flutter_app/features/posts/domain/repositories/posts_privacy_settings_repository.dart';
import 'feed_screen.dart';

const _uuid = Uuid();

typedef EditChatMessageFn =
    Future<(SendChatMessageResult, ConversationMessage?)> Function({
      required P2PService p2pService,
      required MessageRepository messageRepo,
      required ConversationMessage originalMessage,
      required String updatedText,
      required String senderUsername,
      Bridge? bridge,
      String? recipientMlKemPublicKey,
      MediaAttachmentRepository? mediaAttachmentRepo,
      bool emitTimingEvent,
    });

typedef DeleteMessageForMeFn =
    Future<int> Function({
      required ConversationMessage message,
      required MessageRepository messageRepo,
      ReactionRepository? reactionRepo,
      MediaAttachmentRepository? mediaAttachmentRepo,
      MediaFileManager? mediaFileManager,
    });

typedef DeleteMessageForEveryoneFn =
    Future<(SendChatMessageResult, ConversationMessage?)> Function({
      required P2PService p2pService,
      required MessageRepository messageRepo,
      required ConversationMessage originalMessage,
      ReactionRepository? reactionRepo,
      MediaAttachmentRepository? mediaAttachmentRepo,
      MediaFileManager? mediaFileManager,
      Bridge? bridge,
      String? recipientMlKemPublicKey,
      bool emitTimingEvent,
    });

/// Wired widget that connects FeedScreen to business logic.
///
/// Follows the same "Wired" pattern as FirstTimeExperienceWired.
/// Loads identity, builds feed items from the initial contact,
/// and listens for new incoming contact requests.
class FeedWired extends StatefulWidget {
  static const deleteSheetKey = ValueKey('feed-delete-message-sheet');
  static const deletePromptKey = ValueKey('feed-delete-message-prompt');
  static const deleteForMeKey = ValueKey('feed-delete-for-me-action');
  static const deleteForEveryoneKey = ValueKey(
    'feed-delete-for-everyone-action',
  );
  static const deleteCancelKey = ValueKey('feed-delete-cancel-action');

  final IdentityRepository repository;
  final ContactRepository contactRepository;
  final ContactRequestRepository contactRequestRepository;
  final ContactRequestListener contactRequestListener;
  final MessageRepository messageRepository;
  final PostRepository postRepository;
  final MediaAttachmentRepository mediaAttachmentRepository;
  final ChatMessageListener chatMessageListener;
  final Bridge bridge;
  final P2PService p2pService;
  final MediaFileManager mediaFileManager;
  final SecureKeyStore secureKeyStore;
  final ImageProcessor imageProcessor;
  final ActiveConversationTracker? conversationTracker;
  final AudioRecorderService? audioRecorderService;
  final ReactionRepository? reactionRepository;
  final ReactionListener? reactionListener;
  final GroupRepository? groupRepository;
  final GroupMessageRepository? groupMessageRepository;
  final GroupExitDiagnosticRepository? groupExitDiagnosticRepository;
  final GroupInviteDeliveryAttemptRepository?
  groupInviteDeliveryAttemptRepository;
  final GroupReactionReplayOutboxRepository?
  groupReactionReplayOutboxRepository;
  final GroupMessageListener? groupMessageListener;
  final GroupMediaDownloadCoordinator? groupMediaDownloadCoordinator;
  final GroupInviteListener? groupInviteListener;
  final Future<void> Function()? waitForGroupMembershipUpdateIdle;
  final ActiveConversationTracker? groupConversationTracker;
  final IntroductionRepository? introductionRepository;
  // 207: nullable → raw badge semantics when absent, so every existing
  // construction keeps its behavior; the app shell injects the real store.
  final IntroReviewSeenRepository? introReviewSeenRepository;
  final IntroductionListener? introductionListener;
  final AppShellController appShellController;
  final PendingPostTargetStore pendingPostTargetStore;
  final PostsPrivacySettingsRepository postsPrivacySettingsRepository;
  final FeedClearedRepository feedClearedRepository;
  final ContactPresenceSnapshotRepository? contactPresenceSnapshotRepository;
  final NearbyLocationService? nearbyLocationService;
  final EditChatMessageFn editChatMessageFn;
  final DeleteMessageForMeFn deleteMessageForMeFn;
  final DeleteMessageForEveryoneFn deleteMessageForEveryoneFn;
  final TransportMetrics? transportMetrics;
  final ResolveCallWakeHandle? resolveCallWakeHandle;
  final OnCallWakeHandleDistributed? onCallWakeHandleDistributed;
  final AccountMigrationTransferRunFn? accountMigrationRunTransfer;
  final AccountMigrationSizeGate? accountMigrationSizeGate;

  /// 362: linked-device authority for every 1:1 conversation this shell can
  /// push (and for the embedded Orbit host). Null preserves the incumbent
  /// single-target behaviour exactly.
  final DirectConversationRouteAuthority? directRouteAuthority;

  /// 409: forwarded to the Orbit route this shell pushes.
  final OrbitCallActivitySource? orbitCallActivitySource;

  const FeedWired({
    super.key,
    this.directRouteAuthority,
    this.orbitCallActivitySource,
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
    this.groupReactionReplayOutboxRepository,
    this.groupMessageListener,
    this.groupMediaDownloadCoordinator,
    this.groupInviteListener,
    this.waitForGroupMembershipUpdateIdle,
    this.groupConversationTracker,
    this.introductionRepository,
    this.introReviewSeenRepository,
    this.introductionListener,
    required this.appShellController,
    required this.pendingPostTargetStore,
    required this.postsPrivacySettingsRepository,
    required this.feedClearedRepository,
    this.contactPresenceSnapshotRepository,
    this.nearbyLocationService,
    this.editChatMessageFn = editChatMessage,
    this.deleteMessageForMeFn = deleteMessageForMe,
    this.deleteMessageForEveryoneFn = deleteMessageForEveryone,
    this.transportMetrics,
    this.resolveCallWakeHandle,
    this.onCallWakeHandleDistributed,
    this.accountMigrationRunTransfer,
    this.accountMigrationSizeGate,
  });

  @override
  State<FeedWired> createState() => _FeedWiredState();
}

class _FeedWiredState extends State<FeedWired>
    with SingleTickerProviderStateMixin {
  static const _hostSwipeSettleDuration = Duration(milliseconds: 240);
  // 160 B6: per-event feed refreshes (send-fallback / delete / hide /
  // nav-return) reload through a bounded, newest-first page of this size
  // instead of the whole decrypted history.
  static const _feedSnapshotPageSize = 50;
  // 160 A9: focus hydrates the focused contact's full unread set + context via
  // a larger page so a >window thread shows every unread line once opened.
  static const _focusHydrationPageSize = 200;
  // 162 (db-persistence-7): trailing per-contact coalesce window. A drain burst
  // (131/145/146/147 land N rows → N repo-change emits) collapses into ONE
  // materialization per contact instead of re-materializing N times back-to-back.
  static const _feedReloadCoalesceWindow = Duration(milliseconds: 32);
  static const _hostSwipeDecisionThreshold = 12.0;
  static const _hostSwipeCompletionThreshold = 0.28;
  static const _hostSwipeVelocityThreshold = 900.0;

  String _username = 'Username';
  String? _peerId;
  IdentityModel? _identity;
  final FeedStore _feedStore = FeedStore();
  final ValueNotifier<int> _totalUnreadCountNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> _orbitBadgeCountNotifier = ValueNotifier<int>(0);
  final ValueNotifier<FeedRouteChanges?> _mountedOrbitRouteChangesNotifier =
      ValueNotifier<FeedRouteChanges?>(null);
  final FeedReactionStore _reactionStore = FeedReactionStore();
  bool _feedLoaded = false;
  // 141: one-shot guard for the opportunistic notif-open inbox drain.
  bool _didOpportunisticDrain = false;
  final Map<String, String> _draftTexts = {};
  final Map<String, String> _activeQuoteMessageIds = {};
  final SessionReplyTracker _sessionReplies = SessionReplyTracker();
  // 134-P5: focused thread id (1:1=contactPeerId, group='group:<id>',
  // system=contactPeerId) + the outgoing replies sent during the current focus
  // session, keyed the same way (drives append-stay + never-silent retry).
  String? _focusedId;
  final Map<String, List<FeedSessionReply>> _feedSessionOutgoing = {};
  String? _activeFocusPeerId;
  String? _editingContactPeerId;
  String? _editingMessageId;
  StreamSubscription<ContactRequestModel>? _requestSubscription;
  StreamSubscription<ConversationMessage>? _chatSubscription;
  StreamSubscription<ConversationMessage>? _repoChangeSubscription;
  // 194x: conversation read-marking events (peerId) — the aggregate Feed unread
  // badge must drop when a conversation is read on ANY surface, including the
  // orbit avatar tap / notification route that mark read through the repo
  // without traversing the feed's own leave-thread recompute.
  StreamSubscription<String>? _conversationReadSubscription;
  StreamSubscription<ContactModel>? _contactUpdateSubscription;
  StreamSubscription<ReactionChange>? _reactionSubscription;
  StreamSubscription<dynamic>? _groupMessageSubscription;
  StreamSubscription<ReactionChange>? _groupReactionSubscription;
  StreamSubscription<GroupModel>? _groupInviteJoinedSubscription;
  StreamSubscription<PendingGroupInvite>? _pendingGroupInviteSubscription;
  StreamSubscription<IntroductionModel>? _introReceivedSubscription;
  StreamSubscription<IntroductionModel>? _introStatusSubscription;
  // 162: per-contact pending coalesce state + its trailing timer. The
  // repo-change listener and incoming-message handler enqueue here instead of
  // firing a materialization per event; one flush per contact runs after the
  // window. Sticky flags escalate to a full refresh whenever the burst could
  // have dropped a message under the incremental single-id upsert.
  final Map<String, _PendingContactFeedFlush> _pendingContactFlushes = {};
  final Map<String, Timer> _pendingContactFlushTimers = {};
  int _orbitBadgeLoadRequestId = 0;
  ImageQualityPreference _qualityPreference = ImageQualityPreference.compressed;

  String? get _currentSenderDeviceId {
    final peerId = widget.p2pService.currentState.peerId?.trim();
    return peerId == null || peerId.isEmpty ? null : peerId;
  }

  ImageQualityPreference _videoQualityPreference =
      ImageQualityPreference.compressed;
  bool _hasMountedOrbitHost = false;
  late final AnimationController _hostSwipeController;
  VoidCallback? _orbitEmbeddedExitAction;
  bool _orbitRowActionOpen = false;
  double _hostViewportWidth = 0;
  int? _hostSwipePointer;
  Offset? _hostSwipeStartPosition;
  String? _hostSwipeStartTab;
  bool _hostSwipeResolved = false;
  bool _hostSwipeClaimed = false;
  VelocityTracker? _hostSwipeVelocityTracker;
  // 134-P6 gesture arena (TC-35): true while a card-level swipe is live, so the
  // screen-level Feed↔Orbit host swipe yields the gesture to the card.
  bool _feedCardSwipeActive = false;
  // 198 (INV-8): true while an Orbit sculpt edit session is active. The raw
  // host-swipe Listener bypasses the gesture arena, so this flag is the ONLY
  // mechanism keeping a rightward handle drag from sliding the tab to Feed
  // mid-sculpt (mirrors [_orbitRowActionOpen] / [_feedCardSwipeActive]).
  bool _orbitEditSessionActive = false;

  List<FeedItem> get _feedItems => _feedStore.items;
  void _clearEditState({
    String? contactPeerId,
    bool clearDraft = false,
    bool clearFocus = false,
  }) {
    final targetContactPeerId = contactPeerId ?? _editingContactPeerId;
    if (clearDraft && targetContactPeerId != null) {
      _draftTexts.remove(targetContactPeerId);
    }
    if (clearFocus &&
        targetContactPeerId != null &&
        _activeFocusPeerId == targetContactPeerId) {
      _activeFocusPeerId = null;
    }
    _editingContactPeerId = null;
    _editingMessageId = null;
  }

  void _syncComposerStateForContact(
    String contactPeerId,
    Set<String> visibleMessageIds,
  ) {
    var didChange = false;

    if (_editingContactPeerId == contactPeerId &&
        _editingMessageId != null &&
        !visibleMessageIds.contains(_editingMessageId)) {
      _clearEditState(
        contactPeerId: contactPeerId,
        clearDraft: true,
        clearFocus: true,
      );
      didChange = true;
    }

    final activeQuoteId = _activeQuoteMessageIds[contactPeerId];
    if (activeQuoteId != null && !visibleMessageIds.contains(activeQuoteId)) {
      _activeQuoteMessageIds.remove(contactPeerId);
      didChange = true;
    }

    if (didChange && mounted) {
      setState(() {});
    }
  }

  void _markFeedLoaded() {
    if (_feedLoaded || !mounted) return;
    setState(() => _feedLoaded = true);
  }

  @override
  void initState() {
    super.initState();
    _hasMountedOrbitHost = _activeTab == AppShellTab.orbit;
    _hostSwipeController = AnimationController(
      vsync: this,
      duration: _hostSwipeSettleDuration,
      value: _hasMountedOrbitHost ? 1.0 : 0.0,
    );
    widget.appShellController.addListener(_onShellChanged);
    emitFlowEvent(
      layer: 'FL',
      event: 'FEED_FL_SCREEN_INIT',
      details: {'introRepoNull': widget.introductionRepository == null},
    );
    _loadIdentity();
    _loadBackgroundPreference();
    _loadQualityPreference();
    _loadVideoQualityPreference();
    _loadClearedWatermarks();
    _loadFeedFromDatabase();
    _loadTotalUnreadCount();
    _startListeningForContactRequests();
    _startListeningForChatMessages();
    _startListeningForOutgoingMessageChanges();
    _startListeningForConversationReads();
    _startListeningForContactUpdates();
    _startListeningForReactions();
    _startListeningForGroupReactions();
    _startListeningForGroupMessages();
    _startListeningForGroupInvites();
    _startListeningForIntroductions();
    _maybeRequestOpportunisticInboxDrain();
  }

  /// 141: Belt-and-suspenders for the notif-open inbox-drain race. When Feed
  /// becomes the active home — including the Android cold-tap path that lands
  /// on Feed with the conversation route deferred — request one opportunistic
  /// offline-inbox drain. Idempotent (one per State lifetime, never per frame);
  /// the P2PService itself defers the drain until the node has started, so this
  /// is safe to fire eagerly here.
  void _maybeRequestOpportunisticInboxDrain() {
    if (_didOpportunisticDrain) return;
    _didOpportunisticDrain = true;
    unawaited(widget.p2pService.drainOfflineInbox());
  }

  Future<void> _loadIdentity() async {
    try {
      final identity = await widget.repository.loadIdentity();
      if (identity == null || !mounted) return;

      // 206: the Feed header no longer renders the self avatar (Settings moved
      // to the Orbit center avatar), so resolving avatar bytes here is dead.
      setState(() {
        _identity = identity;
        _username = identity.username;
        _peerId = identity.peerId;
      });
      unawaited(_refreshOrbitBadgeCount());
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'FEED_FL_LOAD_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _loadQualityPreference() async {
    final pref = await loadImageQualityPreference(
      secureKeyStore: widget.secureKeyStore,
    );
    if (mounted) {
      setState(() => _qualityPreference = pref);
    }
  }

  Future<void> _loadVideoQualityPreference() async {
    final pref = await loadVideoQualityPreference(
      secureKeyStore: widget.secureKeyStore,
    );
    if (mounted) {
      setState(() => _videoQualityPreference = pref);
    }
  }

  Future<void> _loadBackgroundPreference() async {
    final pref = await loadBackgroundPreference(
      secureKeyStore: widget.secureKeyStore,
    );
    if (mounted) {
      widget.appShellController.setBackgroundPreference(pref);
    }
  }

  /// 134-P4: hydrate the Feed pending-projection's cleared watermarks from the
  /// persistent `feed_cleared_threads` table so cleared/dismissed threads are
  /// filtered out from first paint.
  Future<void> _loadClearedWatermarks() async {
    try {
      final watermarks = await widget.feedClearedRepository
          .getClearedWatermarks();
      if (!mounted) return;
      _feedStore.setClearedWatermarks(watermarks);
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'FEED_FL_CLEARED_LOAD_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _loadFeedFromDatabase() async {
    try {
      final items = await loadFeed(
        contactRepo: widget.contactRepository,
        messageRepo: widget.messageRepository,
        mediaAttachmentRepo: widget.mediaAttachmentRepository,
        mediaFileManager: widget.mediaFileManager,
        groupRepo: widget.groupRepository,
        groupMsgRepo: widget.groupMessageRepository,
      );
      if (!mounted) return;

      _feedStore.replaceAll(items);
      _markFeedLoaded();
      _loadReactionsForFeed();
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'FEED_FL_DB_LOAD_ERROR',
        details: {'error': e.toString()},
      );
      _markFeedLoaded();
    }
  }

  Future<void> _loadTotalUnreadCount() async {
    try {
      final count = await widget.messageRepository
          .getTotalUnreadCountExcludingArchived();
      if (!mounted) return;
      _totalUnreadCountNotifier.value = count;
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'FEED_FL_UNREAD_COUNT_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _refreshOrbitBadgeCount() async {
    final introRepo = widget.introductionRepository;
    final ownPeerId = _peerId;
    final pendingInviteRepo = widget.groupInviteListener?.pendingInviteRepo;
    if ((introRepo == null || ownPeerId == null) && pendingInviteRepo == null) {
      if (mounted) {
        _orbitBadgeCountNotifier.value = 0;
      }
      return;
    }

    final requestId = ++_orbitBadgeLoadRequestId;

    try {
      var introTargetPeerIds = const <String>{};
      if (introRepo != null && ownPeerId != null) {
        await expireOldIntroductions(
          introRepo: introRepo,
          peerId: ownPeerId,
          contactRepo: widget.contactRepository,
          messageRepo: widget.messageRepository,
          bridge: widget.bridge,
        );
        final pendingIntroductions = await loadIntroductionsForUser(
          introRepo: introRepo,
          peerId: ownPeerId,
        );
        introTargetPeerIds = foldedPendingIntroductionTargetPeerIds(
          introductions: pendingIntroductions,
          ownPeerId: ownPeerId,
        );
      }

      var actionableInviteGroupIds = const <String>{};
      if (pendingInviteRepo != null) {
        final invites = await pendingInviteRepo.getPendingInvites();
        // Mirror the list surfaces' B2 materialized filter so the badge equals
        // the number of actionable (not-already-joined) invites rendered.
        final groupRepo = widget.groupRepository;
        Iterable<PendingGroupInvite> actionable = invites;
        if (groupRepo != null) {
          final joinedGroupIds = (await groupRepo.getActiveGroups())
              .map((group) => group.id)
              .toSet();
          actionable = invites.where(
            (invite) => !joinedGroupIds.contains(invite.groupId),
          );
        }
        actionableInviteGroupIds = actionable
            .map((invite) => invite.groupId)
            .toSet();
      }

      // 207: badge = unseen (dock-dismissed items drop out); repo absent →
      // empty seen set → unseen == raw, the INV-4 parity every legacy badge
      // lock rides on.
      var badgeCount =
          introTargetPeerIds.length + actionableInviteGroupIds.length;
      final seenRepo = widget.introReviewSeenRepository;
      if (seenRepo != null) {
        final currentKeys = <String>{
          for (final peerId in introTargetPeerIds)
            introReviewKeyForIntroTarget(peerId),
          for (final groupId in actionableInviteGroupIds)
            introReviewKeyForGroupInvite(groupId),
        };
        final seenKeys = await seenRepo.loadSeenKeys();
        badgeCount = computeUnseenReviewKeys(
          currentKeys: currentKeys,
          seenKeys: seenKeys,
        ).length;
      }

      if (!mounted || requestId != _orbitBadgeLoadRequestId) {
        return;
      }
      _orbitBadgeCountNotifier.value = badgeCount;
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'FEED_FL_ORBIT_BADGE_COUNT_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  void _startListeningForGroupInvites() {
    final listener = widget.groupInviteListener;
    if (listener == null) return;

    _groupInviteJoinedSubscription = listener.groupJoinedStream.listen(
      (_) => unawaited(_refreshOrbitBadgeCount()),
      onError: (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'FEED_GROUP_INVITE_JOINED_STREAM_ERROR',
          details: {'error': error.toString()},
        );
      },
    );

    _pendingGroupInviteSubscription = listener.pendingInviteStream.listen(
      (_) => unawaited(_refreshOrbitBadgeCount()),
      onError: (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'FEED_PENDING_GROUP_INVITE_STREAM_ERROR',
          details: {'error': error.toString()},
        );
      },
    );
  }

  Future<void> _refreshFeed() async {
    await _loadTotalUnreadCount();
    await _loadFeedFromDatabase();
  }

  Future<void> _refreshReactionsForMessageIds(List<String> messageIds) async {
    if (widget.reactionRepository == null || messageIds.isEmpty) {
      return;
    }

    try {
      final reactions = await loadReactionsForConversation(
        reactionRepo: widget.reactionRepository!,
        messageIds: messageIds,
      );
      _reactionStore.replaceForMessageIds(messageIds, reactions);
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'FEED_FL_LOAD_REACTIONS_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _refreshContactFeedItem(
    String contactPeerId, {
    bool refreshUnreadCount = true,
    int? pageSize = _feedSnapshotPageSize,
  }) async {
    try {
      final snapshot = await loadContactFeedSnapshot(
        contactRepo: widget.contactRepository,
        messageRepo: widget.messageRepository,
        contactPeerId: contactPeerId,
        pageSize: pageSize,
        mediaAttachmentRepo: widget.mediaAttachmentRepository,
        mediaFileManager: widget.mediaFileManager,
      );
      if (!mounted) return;

      final nextMessageIds = snapshot.threadItem == null
          ? <String>{}
          : snapshot.threadItem!.messages.map((message) => message.id).toSet();
      _syncComposerStateForContact(contactPeerId, nextMessageIds);

      _feedStore.replaceContactSnapshot(
        contactPeerId: contactPeerId,
        connectionItem: snapshot.connectionItem,
        threadItem: snapshot.threadItem,
      );
      _markFeedLoaded();

      // 160 B7: do NOT prune reactions by page difference. Under the bounded
      // snapshot an older still-present message is evicted from the window but
      // has NOT left the thread, so clearing it would drop live reactions
      // (TC-160-10). Genuine removals clear their own id at the delete/hide
      // call site (see the repo-change listener). We still (re)load reactions
      // for the rendered page.
      await _refreshReactionsForMessageIds(nextMessageIds.toList());

      if (refreshUnreadCount) {
        await _loadTotalUnreadCount();
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'FEED_FL_CONTACT_REFRESH_ERROR',
        details: {'contactPeerId': contactPeerId, 'error': e.toString()},
      );
      await _refreshFeed();
    }
  }

  Future<void> _refreshGroupFeedItem(String groupId) async {
    final groupRepo = widget.groupRepository;
    final groupMsgRepo = widget.groupMessageRepository;
    if (groupRepo == null || groupMsgRepo == null) return;

    try {
      final threadItem = await loadGroupFeedSnapshot(
        groupRepo: groupRepo,
        groupMsgRepo: groupMsgRepo,
        groupId: groupId,
        pageSize: _feedSnapshotPageSize,
        mediaAttachmentRepo: widget.mediaAttachmentRepository,
        mediaFileManager: widget.mediaFileManager,
      );
      if (!mounted) return;

      _feedStore.replaceGroupSnapshot(groupId: groupId, threadItem: threadItem);
      _markFeedLoaded();
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'FEED_FL_GROUP_REFRESH_ERROR',
        details: {'groupId': groupId, 'error': e.toString()},
      );
      await _refreshFeed();
    }
  }

  Future<void> _refreshAllContactsSection({
    bool refreshUnreadCount = true,
  }) async {
    final previousContactMessageIds = _feedItems
        .whereType<ThreadFeedItem>()
        .expand((item) => item.messages)
        .map((message) => message.id)
        .toSet();

    try {
      final contactItems = await loadContactFeedItems(
        contactRepo: widget.contactRepository,
        messageRepo: widget.messageRepository,
        mediaAttachmentRepo: widget.mediaAttachmentRepository,
        mediaFileManager: widget.mediaFileManager,
      );
      if (!mounted) return;

      final nextContactMessageIds = contactItems
          .whereType<ThreadFeedItem>()
          .expand((item) => item.messages)
          .map((message) => message.id)
          .toSet();

      _feedStore.replaceContacts(contactItems);
      _markFeedLoaded();
      _reactionStore.clearMessageIds(
        previousContactMessageIds.difference(nextContactMessageIds),
      );

      await _refreshReactionsForMessageIds(nextContactMessageIds.toList());

      if (refreshUnreadCount) {
        await _loadTotalUnreadCount();
      }

      // 160 A9: a wholesale contact-section reload re-windows every thread. If a
      // 1:1 card is focused, restore its FULL hydrated thread so the open view
      // is not clobbered back to the mount window.
      final focused = _focusedId;
      if (focused != null &&
          !focused.startsWith('group:') &&
          !focused.startsWith('connection:')) {
        await _hydrateFocusedContactThread(focused);
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'FEED_FL_CONTACT_SECTION_REFRESH_ERROR',
        details: {'error': e.toString()},
      );
      await _refreshFeed();
    }
  }

  Future<void> _refreshAllGroupsSection() async {
    try {
      final groupItems = await loadGroupFeedItems(
        groupRepo: widget.groupRepository,
        groupMsgRepo: widget.groupMessageRepository,
        mediaAttachmentRepo: widget.mediaAttachmentRepository,
        mediaFileManager: widget.mediaFileManager,
      );
      if (!mounted) return;

      _feedStore.replaceGroups(groupItems);
      _markFeedLoaded();
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'FEED_FL_GROUP_SECTION_REFRESH_ERROR',
        details: {'error': e.toString()},
      );
      await _refreshFeed();
    }
  }

  ThreadFeedItem? _threadForContact(String contactPeerId) {
    for (final item in _feedItems) {
      if (item is ThreadFeedItem && item.contactPeerId == contactPeerId) {
        return item;
      }
    }
    return null;
  }

  GroupThreadFeedItem? _threadForGroup(String groupId) {
    for (final item in _feedItems) {
      if (item is GroupThreadFeedItem && item.groupId == groupId) {
        return item;
      }
    }
    return null;
  }

  Future<List<MediaAttachment>> _loadResolvedAttachmentsForMessage(
    String messageId, {
    required MediaOwnerLane owner,
    bool requireGroupMediaIntegrity = false,
  }) async {
    final attachments = await widget.mediaAttachmentRepository
        .getAttachmentsForMessage(messageId, owner: owner);
    if (attachments.isEmpty) return const <MediaAttachment>[];

    if (requireGroupMediaIntegrity) {
      return resolveGroupFeedMediaForDisplay(
        attachments: attachments,
        mediaFileManager: widget.mediaFileManager,
      );
    }

    final resolved = <MediaAttachment>[];
    for (final attachment in attachments) {
      if (attachment.localPath == null) {
        resolved.add(attachment);
        continue;
      }

      final absolutePath = await widget.mediaFileManager.resolveStoredPath(
        attachment.localPath!,
      );
      resolved.add(attachment.copyWith(localPath: absolutePath));
    }
    return resolved;
  }

  ThreadMessage _toThreadMessage(ConversationMessage message) {
    final timestamp = DateTime.tryParse(message.timestamp) ?? DateTime.now();
    return ThreadMessage(
      id: message.id,
      text: message.text,
      time: formatMessageTime(message.timestamp),
      timestamp: timestamp,
      isUnread:
          !message.isDeleted && message.isIncoming && message.readAt == null,
      isIncoming: message.isIncoming,
      isDeleted: message.isDeleted,
      status: message.isIncoming ? null : message.status,
      editedAt: message.editedAt,
      quotedMessageId: message.quotedMessageId,
      media: message.media,
      senderPeerId: message.senderPeerId,
    );
  }

  ThreadMessage _toGroupThreadMessage(GroupMessage message) {
    final displayMessage = projectGroupMessageForFeed(message);
    return ThreadMessage(
      id: displayMessage.id,
      text: displayMessage.text,
      time: formatMessageTime(
        displayMessage.timestamp.toUtc().toIso8601String(),
      ),
      timestamp: displayMessage.timestamp,
      isUnread: displayMessage.isIncoming && displayMessage.readAt == null,
      isIncoming: displayMessage.isIncoming,
      status: displayMessage.isIncoming ? null : displayMessage.status,
      quotedMessageId: displayMessage.quotedMessageId,
      senderPeerId: displayMessage.senderPeerId,
      senderUsername: displayMessage.senderUsername,
      media: displayMessage.media,
    );
  }

  /// Merges [next] into a group thread that may be a windowed preview (161).
  /// Mirrors [_mergeContactThreadMessages]: returns the merged list and whether
  /// a genuinely-NEW id was added (so the caller carries+increments
  /// `totalMessageCount`). An off-window-older status flip is dropped so the
  /// window neither grows nor double-counts.
  ({List<ThreadMessage> messages, bool added}) _mergeGroupThreadMessages(
    GroupThreadFeedItem? currentThread,
    ThreadMessage next,
  ) {
    final current = currentThread?.messages ?? const <ThreadMessage>[];
    final index = current.indexWhere((message) => message.id == next.id);
    if (index >= 0) {
      final updated = List<ThreadMessage>.from(current);
      updated[index] = next;
      updated.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      return (messages: updated, added: false);
    }

    final windowed =
        currentThread != null &&
        currentThread.totalMessageCount > current.length;
    if (windowed && current.isNotEmpty) {
      final windowFloor = current.first.timestamp; // sorted asc → oldest loaded
      if (next.timestamp.isBefore(windowFloor)) {
        // Off-window-older flip — do not add, do not count.
        return (messages: current, added: false);
      }
    }

    final updated = List<ThreadMessage>.from(current)..add(next);
    updated.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return (messages: updated, added: true);
  }

  /// Merges [next] into a 1:1 contact thread that may be a windowed preview
  /// (160 B8). Returns the merged list and whether a genuinely-NEW id was
  /// added (so the caller can carry+increment `totalMessageCount`).
  ///
  /// Off-window-flip guard: when the thread is windowed and [next] is NOT
  /// already present and is OLDER than the window floor, it is an off-window
  /// status flip of an old row — NOT a genuinely-new message. Dropping it keeps
  /// the window from growing (reinserting an old row) and from double-counting
  /// the total. A genuinely-new incoming is newest by definition → it enters
  /// the window and counts.
  ({List<ThreadMessage> messages, bool added}) _mergeContactThreadMessages(
    ThreadFeedItem? currentThread,
    ThreadMessage next,
  ) {
    final current = currentThread?.messages ?? const <ThreadMessage>[];
    final index = current.indexWhere((message) => message.id == next.id);
    if (index >= 0) {
      final updated = List<ThreadMessage>.from(current);
      updated[index] = next;
      updated.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      return (messages: updated, added: false);
    }

    final windowed =
        currentThread != null &&
        currentThread.totalMessageCount > current.length;
    if (windowed && current.isNotEmpty) {
      final windowFloor = current.first.timestamp; // sorted asc → oldest loaded
      if (next.timestamp.isBefore(windowFloor)) {
        // Off-window-older flip — do not add, do not count.
        return (messages: current, added: false);
      }
    }

    final updated = List<ThreadMessage>.from(current)..add(next);
    updated.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return (messages: updated, added: true);
  }

  DateTime? _maxDate(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.isAfter(b) ? a : b;
  }

  DateTime? _lastSentTimestamp(List<ThreadMessage> messages) {
    for (var index = messages.length - 1; index >= 0; index--) {
      final message = messages[index];
      if (!message.isIncoming && !message.isDeleted) {
        return message.timestamp;
      }
    }
    return null;
  }

  /// Builds a 1:1 thread card from a (possibly windowed) message list.
  ///
  /// [totalMessageCount] is the carried/incremented true total (160 B8); null
  /// means "no window" → the model defaults it to `messages.length`.
  /// [carriedLastOutgoingAt] is the prior thread's last-outgoing signal
  /// (`summary.lastOutgoingAt`, 160 A4) so a reply that sits OFF the loaded
  /// window does not false-negative `hasReply` / flip the card to `unread`.
  ThreadFeedItem _buildThreadFeedItem({
    required ContactModel contact,
    required List<ThreadMessage> messages,
    int? totalMessageCount,
    DateTime? carriedLastOutgoingAt,
  }) {
    // Effective last-outgoing: the newer of the carried summary signal and any
    // outgoing inside the loaded window. The window always covers the unread
    // run (newest), so unread derivation from the window is exact.
    final lastOutgoingAt = _maxDate(
      carriedLastOutgoingAt,
      _lastSentTimestamp(messages),
    );
    final hasUnreadIncoming = messages.any(
      (message) => message.isIncoming && message.isUnread && !message.isDeleted,
    );
    final hasSentMessages = lastOutgoingAt != null;
    final ConversationState state;
    if (hasUnreadIncoming && hasSentMessages) {
      state = ConversationState.active;
    } else if (hasUnreadIncoming) {
      state = ConversationState.unread;
    } else if (hasSentMessages) {
      state = ConversationState.replied;
    } else {
      state = ConversationState.read;
    }
    return ThreadFeedItem(
      id: 'thread_${contact.peerId}',
      timestamp: messages.isEmpty ? DateTime.now() : messages.last.timestamp,
      contactPeerId: contact.peerId,
      contactUsername: contact.username,
      messages: messages,
      unreadCount: messages
          .where((message) => message.isUnread && !message.isDeleted)
          .length,
      isUnreadCard:
          state == ConversationState.unread ||
          state == ConversationState.active,
      conversationState: state,
      lastRepliedAt: lastOutgoingAt,
      isBlocked: contact.isBlocked,
      totalMessageCount: totalMessageCount,
    );
  }

  GroupThreadFeedItem _buildGroupThreadFeedItem({
    required GroupModel group,
    required List<ThreadMessage> messages,
    int? totalMessageCount,
    DateTime? carriedLastOutgoingAt,
  }) {
    // 161: effective last-outgoing is the newer of the carried summary signal
    // and any outgoing inside the window. The window always covers the unread
    // run (newest), so unread/state derive exactly from it; the carried signal
    // keeps `replied`/`active` correct when an old reply is off the window.
    final lastOutgoingAt = _maxDate(
      carriedLastOutgoingAt,
      _lastSentTimestamp(messages),
    );
    final hasUnreadIncoming = messages.any(
      (message) => message.isIncoming && message.isUnread && !message.isDeleted,
    );
    final hasSentMessages = lastOutgoingAt != null;
    final ConversationState state;
    if (hasUnreadIncoming && hasSentMessages) {
      state = ConversationState.active;
    } else if (hasUnreadIncoming) {
      state = ConversationState.unread;
    } else if (hasSentMessages) {
      state = ConversationState.replied;
    } else {
      state = ConversationState.read;
    }
    return GroupThreadFeedItem(
      id: 'group_thread_${group.id}',
      timestamp: messages.isEmpty ? group.createdAt : messages.last.timestamp,
      groupId: group.id,
      groupName: group.name,
      groupType: group.type,
      myRole: group.myRole,
      isDissolved: group.isDissolved,
      avatarPath: group.avatarPath,
      avatarCacheBustKey:
          group.lastMetadataEventAt?.toUtc().toIso8601String() ??
          group.avatarBlobId,
      messages: messages,
      unreadCount: messages.where((message) => message.isUnread).length,
      conversationState: state,
      totalMessageCount: totalMessageCount,
      lastRepliedAt: lastOutgoingAt,
    );
  }

  Future<void> _applyIncomingContactMessageToFeed(
    ConversationMessage message, {
    bool refreshUnreadCount = true,
  }) async {
    try {
      if (message.isHidden) {
        await _refreshContactFeedItem(
          message.contactPeerId,
          refreshUnreadCount: refreshUnreadCount,
        );
        return;
      }

      final contact = await widget.contactRepository.getContact(
        message.contactPeerId,
      );
      if (contact == null || contact.isArchived) {
        await _refreshContactFeedItem(
          message.contactPeerId,
          refreshUnreadCount: refreshUnreadCount,
        );
        return;
      }

      final displayMessage = message.copyWith(
        media: message.isDeleted
            ? const <MediaAttachment>[]
            : await _loadResolvedAttachmentsForMessage(
                message.id,
                owner: MediaOwnerLane.direct,
              ),
      );
      final currentThread = _threadForContact(contact.peerId);
      final merge = _mergeContactThreadMessages(
        currentThread,
        _toThreadMessage(displayMessage),
      );
      // 160 B8: carry the prior total forward and increment ONLY on a
      // genuinely-new id (an off-window status flip neither grows the window
      // nor counts). A brand-new thread leaves total null → model defaults it
      // to messages.length.
      final priorTotal = currentThread?.totalMessageCount;
      final nextTotal = priorTotal == null
          ? null
          : priorTotal + (merge.added ? 1 : 0);

      _feedStore.replaceContactSnapshot(
        contactPeerId: contact.peerId,
        connectionItem: ConnectionFeedItem.fromContact(
          contact,
          hasConversationHistory: true,
        ),
        threadItem: _buildThreadFeedItem(
          contact: contact,
          messages: merge.messages,
          totalMessageCount: nextTotal,
          carriedLastOutgoingAt: currentThread?.lastRepliedAt,
        ),
      );
      _markFeedLoaded();

      if (displayMessage.isDeleted) {
        _reactionStore.clearMessageIds({displayMessage.id});
      }

      if (refreshUnreadCount) {
        await _loadTotalUnreadCount();
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'FEED_FL_CONTACT_INCREMENTAL_UPDATE_ERROR',
        details: {
          'contactPeerId': message.contactPeerId,
          'error': e.toString(),
        },
      );
      await _refreshContactFeedItem(
        message.contactPeerId,
        refreshUnreadCount: refreshUnreadCount,
      );
    }
  }

  /// 160 B5: merges a held outgoing message into the contact's in-memory thread
  /// with no DB read (send-success path). Carries `totalMessageCount` forward
  /// and dedupes by id, so it cooperates with the later status-flip merge.
  void _mergeOutgoingContactMessageIntoFeed(
    ContactModel contact,
    ConversationMessage message,
  ) {
    final currentThread = _threadForContact(contact.peerId);
    final merge = _mergeContactThreadMessages(
      currentThread,
      _toThreadMessage(message),
    );
    final priorTotal = currentThread?.totalMessageCount;
    final nextTotal = priorTotal == null
        ? null
        : priorTotal + (merge.added ? 1 : 0);

    _feedStore.replaceContactSnapshot(
      contactPeerId: contact.peerId,
      connectionItem: ConnectionFeedItem.fromContact(
        contact,
        hasConversationHistory: true,
      ),
      threadItem: _buildThreadFeedItem(
        contact: contact,
        messages: merge.messages,
        totalMessageCount: nextTotal,
        carriedLastOutgoingAt: currentThread?.lastRepliedAt,
      ),
    );
    _markFeedLoaded();
  }

  Future<void> _applyContactUpdateToFeed(ContactModel contact) async {
    if (contact.isArchived) {
      await _refreshContactFeedItem(contact.peerId);
      return;
    }

    final currentThread = _threadForContact(contact.peerId);
    // Carry the connection's history flag forward (160 A5): a contact-update for
    // an all-read contact (no materialized thread) must keep suppressing its
    // "new connection" letter.
    final hadHistory =
        currentThread != null ||
        (_feedStore
                .connectionForContact(contact.peerId)
                ?.hasConversationHistory ??
            false);
    _feedStore.replaceContactSnapshot(
      contactPeerId: contact.peerId,
      connectionItem: ConnectionFeedItem.fromContact(
        contact,
        hasConversationHistory: hadHistory,
      ),
      threadItem: currentThread == null
          ? null
          : ThreadFeedItem(
              id: currentThread.id,
              timestamp: currentThread.timestamp,
              contactPeerId: contact.peerId,
              contactUsername: contact.username,
              messages: currentThread.messages,
              unreadCount: currentThread.unreadCount,
              isUnreadCard: currentThread.isUnreadCard,
              conversationState: currentThread.conversationState,
              lastRepliedAt: currentThread.lastRepliedAt,
              isBlocked: contact.isBlocked,
              totalMessageCount: currentThread.totalMessageCount,
            ),
    );
    _markFeedLoaded();
  }

  Future<void> _applyIncomingGroupMessageToFeed(GroupMessage message) async {
    final groupRepo = widget.groupRepository;
    if (groupRepo == null) {
      return;
    }

    try {
      final group = await groupRepo.getGroup(message.groupId);
      if (group == null || group.isArchived) {
        await _refreshGroupFeedItem(message.groupId);
        return;
      }

      final displayMessage = groupMessageAllowsOrdinaryFeedDerivatives(message)
          ? message.copyWith(
              media: await _loadResolvedAttachmentsForMessage(
                message.id,
                owner: MediaOwnerLane.group,
                requireGroupMediaIntegrity: true,
              ),
            )
          : projectGroupMessageForFeed(message);
      final currentThread = _threadForGroup(group.id);
      final merge = _mergeGroupThreadMessages(
        currentThread,
        _toGroupThreadMessage(displayMessage),
      );
      // 161: carry the prior summary total forward and increment ONLY on a
      // genuinely-new id (an off-window status flip neither grows the window nor
      // counts), so a live group message never drifts the total to the windowed
      // slice length. A brand-new thread leaves total null → model defaults it.
      final priorTotal = currentThread?.totalMessageCount;
      final nextTotal = priorTotal == null
          ? null
          : priorTotal + (merge.added ? 1 : 0);

      _feedStore.replaceGroupSnapshot(
        groupId: group.id,
        threadItem: _buildGroupThreadFeedItem(
          group: group,
          messages: merge.messages,
          totalMessageCount: nextTotal,
          carriedLastOutgoingAt: currentThread?.lastRepliedAt,
        ),
      );
      _markFeedLoaded();
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'FEED_FL_GROUP_INCREMENTAL_UPDATE_ERROR',
        details: {'groupId': message.groupId, 'error': e.toString()},
      );
      await _refreshGroupFeedItem(message.groupId);
    }
  }

  Future<void> _applyRouteChanges(FeedRouteChanges? changes) async {
    if (changes == null || !changes.hasChanges) return;

    var shouldReloadUnreadCount = false;

    if (changes.reloadAllContacts) {
      await _refreshAllContactsSection(refreshUnreadCount: false);
      shouldReloadUnreadCount = true;
    } else if (changes.changedContactPeerIds.isNotEmpty) {
      for (final peerId in changes.changedContactPeerIds) {
        _sessionReplies.clear(peerId);
        await _refreshContactFeedItem(peerId, refreshUnreadCount: false);
      }
      shouldReloadUnreadCount = true;
    }

    if (changes.reloadAllGroups) {
      await _refreshAllGroupsSection();
    } else if (changes.changedGroupIds.isNotEmpty) {
      for (final groupId in changes.changedGroupIds) {
        _sessionReplies.clear('group:$groupId');
        await _refreshGroupFeedItem(groupId);
      }
    }

    if (shouldReloadUnreadCount) {
      await _loadTotalUnreadCount();
    }

    if (changes.refreshPendingIntroductions) {
      await _refreshOrbitBadgeCount();
    }
  }

  void _startListeningForContactRequests() {
    _requestSubscription = widget.contactRequestListener.requestStream.listen(
      _onContactRequest,
      onError: (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'FEED_REQUEST_STREAM_ERROR',
          details: {'error': error.toString()},
        );
      },
      onDone: () {
        emitFlowEvent(
          layer: 'FL',
          event: 'FEED_REQUEST_STREAM_DONE',
          details: {},
        );
      },
    );
  }

  void _onContactRequest(ContactRequestModel request) {
    emitFlowEvent(
      layer: 'FL',
      event: 'FEED_FL_CONTACT_REQUEST_RECEIVED',
      details: {
        'peerId': request.peerId.substring(0, 10),
        'username': request.username,
      },
    );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ContactRequestDialog(
        request: request,
        onAccept: () => _acceptRequest(ctx, request),
        onDecline: () => _declineRequest(ctx, request),
      ),
    );
  }

  Future<void> _acceptRequest(
    BuildContext ctx,
    ContactRequestModel request,
  ) async {
    Navigator.pop(ctx);

    final result = await acceptAndReciprocateContactRequest(
      requestRepo: widget.contactRequestRepository,
      contactRepo: widget.contactRepository,
      peerId: request.peerId,
      p2pService: widget.p2pService,
      identityRepo: widget.repository,
      bridge: widget.bridge,
      onProfileDownloaded: widget.chatMessageListener.emitContactUpdate,
      resolveCallWakeHandle: widget.resolveCallWakeHandle,
      onCallWakeHandleDistributed: widget.onCallWakeHandleDistributed,
    );

    if (!mounted) return;

    if (result == AcceptContactRequestResult.success ||
        result == AcceptContactRequestResult.notPending) {
      final contact = request.toContactModel();
      final alreadyExists = _feedItems.any(
        (item) =>
            item is ConnectionFeedItem && item.contactPeerId == contact.peerId,
      );
      if (!alreadyExists) {
        final item = ConnectionFeedItem.fromContact(contact);
        _feedStore.upsertConnection(item);
      }
      // 215: mirror the notification-tap accept — open the 1:1 chat for the
      // newly-accepted peer. Popping back reveals the connection card upserted
      // above, so the Feed presence is preserved.
      final openContact =
          await widget.contactRepository.getContact(request.peerId) ?? contact;
      if (!mounted) return;
      unawaited(_openConversationForContact(openContact));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.error_add_contact),
          backgroundColor: Colors.red[700],
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _declineRequest(
    BuildContext ctx,
    ContactRequestModel request,
  ) async {
    Navigator.pop(ctx);

    await declineContactRequest(
      requestRepo: widget.contactRequestRepository,
      peerId: request.peerId,
    );
  }

  void _startListeningForChatMessages() {
    _chatSubscription = widget.chatMessageListener.incomingMessageStream.listen(
      _onIncomingChatMessage,
      onError: (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'FEED_CHAT_STREAM_ERROR',
          details: {'error': error.toString()},
        );
      },
      onDone: () {
        emitFlowEvent(layer: 'FL', event: 'FEED_CHAT_STREAM_DONE', details: {});
      },
    );
  }

  void _startListeningForOutgoingMessageChanges() {
    final messageRepo = widget.messageRepository;
    if (messageRepo is! MessageRepositoryChangeSource) {
      return;
    }

    final changeSource = messageRepo as MessageRepositoryChangeSource;
    _repoChangeSubscription = changeSource.messageChanges
        .where(
          (message) =>
              !message.isIncoming && _shouldProcessRepositoryChange(message),
        )
        .listen(
          (message) {
            if (!mounted) return;
            // 160 B7: clear a genuinely-removed message's reactions eagerly (the
            // coalesced refresh no longer prunes by page diff, so off-page
            // survivors keep their reactions — TC-160-10). 162: defer only the
            // materialization — enqueue per contact; the sticky-destructive flag
            // escalates a delete/hide to a full `_refreshContactFeedItem`.
            if (message.isDeleted) {
              _reactionStore.clearMessageIds({message.id});
            }
            _enqueueContactFeedFlush(message, refreshUnreadCount: false);
          },
          onError: (error) {
            emitFlowEvent(
              layer: 'FL',
              event: 'FEED_REPO_CHANGE_STREAM_ERROR',
              details: {'error': error.toString()},
            );
          },
        );
  }

  /// 194x: recompute the aggregate unread badge whenever a conversation is
  /// marked read. `markConversationAsRead` writes silently to the DB and does
  /// NOT emit on [MessageRepositoryChangeSource.messageChanges], so the
  /// outgoing-change listener above never catches a read. The only feed path
  /// that recomputes on read today is the feed's own leave-thread handler — a
  /// read from the orbit avatar tap, a notification route, or the all-chats list
  /// left the Feed badge stale until this seam.
  void _startListeningForConversationReads() {
    final messageRepo = widget.messageRepository;
    if (messageRepo is! ConversationReadEventSource) {
      return;
    }
    final readSource = messageRepo as ConversationReadEventSource;
    _conversationReadSubscription = readSource.conversationReadStream.listen(
      (_) {
        if (!mounted) return;
        unawaited(_loadTotalUnreadCount());
      },
      onError: (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'FEED_READ_STREAM_ERROR',
          details: {'error': error.toString()},
        );
      },
    );
  }

  bool _shouldProcessRepositoryChange(ConversationMessage message) =>
      message.isDeleted ||
      message.isHidden ||
      _shouldRefreshFromRepositoryChange(message.status);

  bool _shouldRefreshFromRepositoryChange(String status) =>
      status == 'sent' || status == 'delivered' || status == 'failed';

  void _onIncomingChatMessage(ConversationMessage message) {
    if (!mounted) return;
    // Eager — must NOT be deferred behind the coalesce timer.
    _sessionReplies.clear(message.contactPeerId);
    // 162: incoming emits post-persist (chat_message_listener), so a coalesced
    // full refresh would also surface it; the incremental apply is kept only as
    // a CPU optimization for the single-id status-flip burst. refreshUnreadCount
    // defaults to true here (the unread-badge recompute source).
    _enqueueContactFeedFlush(message, refreshUnreadCount: true);
  }

  /// 162: enqueue a per-contact feed materialization, collapsing a same-contact
  /// burst into ONE trailing flush. All flags are STICKY (a later event never
  /// clears them); [refreshUnreadCount] is OR-accumulated so a mixed incoming
  /// (true) + outgoing (false) burst still recomputes the unread count once.
  void _enqueueContactFeedFlush(
    ConversationMessage message, {
    required bool refreshUnreadCount,
  }) {
    final peerId = message.contactPeerId;
    final pending = _pendingContactFlushes[peerId];
    if (pending == null) {
      _pendingContactFlushes[peerId] = _PendingContactFeedFlush(
        latestMessage: message,
        firstPendingId: message.id,
        sawDistinctIds: false,
        sawDestructive: message.isDeleted || message.isHidden,
        sawRefreshUnread: refreshUnreadCount,
      );
    } else {
      pending.latestMessage = message;
      if (message.id != pending.firstPendingId) pending.sawDistinctIds = true;
      if (message.isDeleted || message.isHidden) pending.sawDestructive = true;
      if (refreshUnreadCount) pending.sawRefreshUnread = true;
    }
    _pendingContactFlushTimers[peerId]?.cancel();
    _pendingContactFlushTimers[peerId] = Timer(
      _feedReloadCoalesceWindow,
      () => _flushContactFeedFlush(peerId),
    );
  }

  void _flushContactFeedFlush(String peerId) {
    _pendingContactFlushTimers.remove(peerId);
    final pending = _pendingContactFlushes.remove(peerId);
    if (pending == null || !mounted) return;
    // A burst that saw a delete/hide (sawDestructive) OR more than one distinct
    // id (sawDistinctIds) cannot be safely replayed through the incremental
    // single-id upsert — it would lose a delete-followed-by-send or an earlier
    // distinct id. Escalate to a full snapshot reload: last-write-wins from the
    // DB, surfaces every persisted id, and a non-hidden delete tombstone renders
    // as an empty isDeleted row (its visible-vs-gone outcome stays owned by the
    // loader's hiddenAt gate — do NOT purge it here).
    if (pending.sawDestructive || pending.sawDistinctIds) {
      unawaited(
        _refreshContactFeedItem(
          peerId,
          refreshUnreadCount: pending.sawRefreshUnread,
        ),
      );
    } else {
      // Hot path: all-same-single-id, no delete — a status-flip burst. The
      // incremental in-memory apply of the latest state is sufficient.
      unawaited(
        _applyIncomingContactMessageToFeed(
          pending.latestMessage,
          refreshUnreadCount: pending.sawRefreshUnread,
        ),
      );
    }
  }

  void _startListeningForContactUpdates() {
    _contactUpdateSubscription = widget.chatMessageListener.contactUpdatedStream
        .listen(
          _onContactUpdated,
          onError: (error) {
            emitFlowEvent(
              layer: 'FL',
              event: 'FEED_CONTACT_UPDATE_STREAM_ERROR',
              details: {'error': error.toString()},
            );
          },
          onDone: () {
            emitFlowEvent(
              layer: 'FL',
              event: 'FEED_CONTACT_UPDATE_STREAM_DONE',
              details: {},
            );
          },
        );
  }

  void _onContactUpdated(ContactModel contact) {
    if (!mounted) return;
    unawaited(_applyContactUpdateToFeed(contact));
  }

  void _onSendMessage(ConnectionFeedItem item) async {
    final contact = await widget.contactRepository.getContact(
      item.contactPeerId,
    );
    if (contact == null || !mounted) return;
    await _openConversationForContact(contact);
  }

  /// Opens the 1:1 [ConversationWired] for [contact] and restores the
  /// per-conversation reply state + feed-item refresh on pop. Shared by the
  /// send-message affordance and the contact-request accept flow (215) so the
  /// deps block lives in exactly one place.
  Future<void> _openConversationForContact(ContactModel contact) async {
    _clearFeedComposerFocus();
    await Navigator.of(context).push(
      buildConversationRoute(
        builder: (_) => ConversationWired(
          directEventFanout:
              widget.directRouteAuthority.resolvedDirectEventFanout,
          directDeviceTrust:
              widget.directRouteAuthority.resolvedDirectDeviceTrust,
          modalityGate: widget.directRouteAuthority.resolvedModalityGate,
          outgoingCallCapability:
              widget.directRouteAuthority.resolvedOutgoingCallCapability,
          callTimelineSource:
              widget.directRouteAuthority.resolvedCallTimelineSource,
          contact: contact,
          identityRepo: widget.repository,
          messageRepo: widget.messageRepository,
          chatMessageListener: widget.chatMessageListener,
          p2pService: widget.p2pService,
          bridge: widget.bridge,
          contactRepo: widget.contactRepository,
          mediaAttachmentRepo: widget.mediaAttachmentRepository,
          mediaFileManager: widget.mediaFileManager,
          imageProcessor: widget.imageProcessor,
          qualityPreference: _qualityPreference,
          videoQualityPreference: _videoQualityPreference,
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
          transportMetrics: widget.transportMetrics,
        ),
      ),
    );
    _sessionReplies.clear(contact.peerId);
    unawaited(_refreshContactFeedItem(contact.peerId));
  }

  void _onReplyToMessage(String contactPeerId) async {
    final contact = await widget.contactRepository.getContact(contactPeerId);
    if (contact == null || !mounted) return;

    _clearFeedComposerFocus();
    Navigator.of(context)
        .push(
          buildConversationRoute(
            builder: (_) => ConversationWired(
              directEventFanout:
                  widget.directRouteAuthority.resolvedDirectEventFanout,
              directDeviceTrust:
                  widget.directRouteAuthority.resolvedDirectDeviceTrust,
              modalityGate: widget.directRouteAuthority.resolvedModalityGate,
              outgoingCallCapability:
                  widget.directRouteAuthority.resolvedOutgoingCallCapability,
              callTimelineSource:
                  widget.directRouteAuthority.resolvedCallTimelineSource,
              contact: contact,
              identityRepo: widget.repository,
              messageRepo: widget.messageRepository,
              chatMessageListener: widget.chatMessageListener,
              p2pService: widget.p2pService,
              bridge: widget.bridge,
              contactRepo: widget.contactRepository,
              mediaAttachmentRepo: widget.mediaAttachmentRepository,
              mediaFileManager: widget.mediaFileManager,
              imageProcessor: widget.imageProcessor,
              qualityPreference: _qualityPreference,
              videoQualityPreference: _videoQualityPreference,
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
              transportMetrics: widget.transportMetrics,
            ),
          ),
        )
        .then((_) {
          _sessionReplies.clear(contactPeerId);
          unawaited(_refreshContactFeedItem(contactPeerId));
        });
  }

  Future<void> _loadReactionsForFeed() async {
    if (widget.reactionRepository == null) return;
    final messageIds = _feedStore.contactMessageIds.toList();
    if (messageIds.isEmpty) {
      _reactionStore.replaceAll(const {});
      return;
    }
    try {
      final reactions = await loadReactionsForConversation(
        reactionRepo: widget.reactionRepository!,
        messageIds: messageIds,
      );
      _reactionStore.replaceAll(reactions);
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'FEED_FL_LOAD_REACTIONS_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  void _startListeningForReactions() {
    if (widget.reactionListener == null) return;
    _reactionSubscription = widget
        .reactionListener!
        .incomingReactionChangeStream
        .listen(
          _onIncomingReactionChange,
          onError: (error) {
            emitFlowEvent(
              layer: 'FL',
              event: 'FEED_REACTION_STREAM_ERROR',
              details: {'error': error.toString()},
            );
          },
        );
  }

  void _onIncomingReactionChange(ReactionChange change) {
    if (!mounted) return;
    if (!_feedStore.containsMessageId(change.messageId)) return;
    _reactionStore.applyChange(change);
  }

  void _startListeningForGroupReactions() {
    final listener = widget.groupMessageListener;
    if (listener == null) return;
    _groupReactionSubscription = listener.groupReactionChangeStream.listen(
      (change) {
        if (!mounted) return;
        _reactionStore.applyChange(change);
      },
      onError: (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'FEED_GROUP_REACTION_STREAM_ERROR',
          details: {'error': error.toString()},
        );
      },
    );
  }

  void _startListeningForGroupMessages() {
    final listener = widget.groupMessageListener;
    if (listener == null) return;
    _groupMessageSubscription = listener.groupMessageStream.listen(
      (message) {
        if (!mounted) return;
        _sessionReplies.clear('group:${message.groupId}');
        unawaited(_applyIncomingGroupMessageToFeed(message));
      },
      onError: (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'FEED_GROUP_MSG_STREAM_ERROR',
          details: {'error': error.toString()},
        );
      },
    );
  }

  void _startListeningForIntroductions() {
    final listener = widget.introductionListener;
    if (listener == null) return;

    _introReceivedSubscription = listener.introReceivedStream.listen(
      (_) => unawaited(_refreshOrbitBadgeCount()),
      onError: (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'FEED_INTRO_RECEIVED_STREAM_ERROR',
          details: {'error': error.toString()},
        );
      },
    );

    _introStatusSubscription = listener.introStatusChangedStream.listen(
      (intro) {
        unawaited(_refreshOrbitBadgeCount());
        final ownPeerId = _peerId;
        if (!mounted || ownPeerId == null) return;
        if (intro.status != IntroductionOverallStatus.mutualAccepted) return;

        final otherPeerId = intro.recipientId == ownPeerId
            ? intro.introducedId
            : intro.recipientId;
        if (otherPeerId.isEmpty) return;

        unawaited(_refreshContactFeedItem(otherPeerId));
      },
      onError: (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'FEED_INTRO_STATUS_STREAM_ERROR',
          details: {'error': error.toString()},
        );
      },
    );
  }

  Future<GroupModel> _resolveGroupForThread(
    GroupThreadFeedItem groupThread,
  ) async {
    final groupRepo = widget.groupRepository;
    final persisted = await groupRepo?.getGroup(groupThread.groupId);
    if (persisted != null) {
      return persisted;
    }

    return GroupModel(
      id: groupThread.groupId,
      name: groupThread.groupName,
      type: groupThread.groupType,
      topicName: '/mknoon/group/${groupThread.groupId}',
      createdAt: DateTime.now(),
      createdBy: '',
      myRole: groupThread.myRole,
      isDissolved: groupThread.isDissolved,
    );
  }

  Future<void> _openGroupConversation(
    GroupThreadFeedItem groupThread, {
    List<PendingComposerMedia>? initialPendingMedia,
    List<File>? initialAttachments,
  }) async {
    final groupRepo = widget.groupRepository;
    final msgRepo = widget.groupMessageRepository;
    final listener = widget.groupMessageListener;
    if (groupRepo == null || msgRepo == null || listener == null) return;

    final group = await _resolveGroupForThread(groupThread);
    if (!mounted) return;

    _clearFeedComposerFocus();
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => GroupConversationWired(
              group: group,
              groupRepo: groupRepo,
              msgRepo: msgRepo,
              groupMessageListener: listener,
              groupMediaDownloadCoordinator:
                  widget.groupMediaDownloadCoordinator,
              openAnnouncementSenderConversation: _openConversationForContact,
              inviteDeliveryAttemptRepo:
                  widget.groupInviteDeliveryAttemptRepository,
              bridge: widget.bridge,
              identityRepo: widget.repository,
              contactRepo: widget.contactRepository,
              p2pService: widget.p2pService,
              mediaAttachmentRepo: widget.mediaAttachmentRepository,
              mediaFileManager: widget.mediaFileManager,
              imageProcessor: widget.imageProcessor,
              qualityPreference: _qualityPreference,
              videoQualityPreference: _videoQualityPreference,
              audioRecorderService: widget.audioRecorderService,
              groupConversationTracker: widget.groupConversationTracker,
              reactionRepo: widget.reactionRepository,
              groupReactionReplayOutboxRepository:
                  widget.groupReactionReplayOutboxRepository,
              initialPendingMedia: initialPendingMedia,
              initialAttachments: initialAttachments,
              backgroundPreference:
                  widget.appShellController.backgroundPreference,
              forwardMessageRepository: widget.messageRepository,
              forwardChatMessageListener: widget.chatMessageListener,
            ),
          ),
        )
        .then((_) {
          _sessionReplies.clear('group:${groupThread.groupId}');
          unawaited(_refreshGroupFeedItem(groupThread.groupId));
        });
  }

  void _onGroupTap(GroupThreadFeedItem groupThread) {
    unawaited(_openGroupConversation(groupThread));
  }

  String get _activeTab => widget.appShellController.activeTab;

  void _clearFeedComposerFocus({bool notify = true}) {
    FocusManager.instance.primaryFocus?.unfocus();
    final hadLegacy = _activeFocusPeerId != null;
    // 134: leaving the feed surface (host-swipe to Orbit, tab switch, opening a
    // full conversation) also ENDS the new focus session — retract the shared
    // composer and unpin the focused thread (else it stays mounted/pinned).
    final hadNewFocus = _focusedId != null;
    if (!hadLegacy && !hadNewFocus) {
      return;
    }

    _activeFocusPeerId = null;
    if (hadNewFocus) {
      _focusedId = null;
      _feedSessionOutgoing.clear();
      _feedStore.setPinnedThread(null);
    }

    if (notify && mounted) {
      setState(() {});
    }
  }

  // ── 134-P5: focus + shared composer ──────────────────────────────────────

  void _onFocusCard(String threadId) {
    if (_focusedId == threadId) return;
    setState(() => _focusedId = threadId);
    // Pin the focused thread so it stays visible after you reply (append-stay):
    // once answered it leaves the pending set, but the composer keeps appending
    // under it until focus clears.
    _feedStore.setPinnedThread(threadId);
    // 160 A9: mount loads only a per-contact preview window; on focus hydrate
    // the focused 1:1 thread's FULL unread set (+ context) so the opened card
    // renders every unread line and its reactions. NO read-mark on focus
    // (REG-INV3) — read-marking stays on _leaveFocusedThread.
    if (!threadId.startsWith('group:') && !threadId.startsWith('connection:')) {
      unawaited(_hydrateFocusedContactThread(threadId));
    }
  }

  /// 160 A9: loads the focused 1:1 contact's full thread (larger page) and
  /// replaces its snapshot. Skips the work if focus moved on before the load
  /// completed (clobber-safe). Never marks the conversation read.
  Future<void> _hydrateFocusedContactThread(String contactPeerId) async {
    if (_focusedId != contactPeerId) return;
    await _refreshContactFeedItem(
      contactPeerId,
      refreshUnreadCount: false,
      pageSize: _focusHydrationPageSize,
    );
  }

  void _onClearFocus() {
    final threadId = _focusedId;
    if (threadId == null) {
      FocusManager.instance.primaryFocus?.unfocus();
      return;
    }
    // 135 B2/B4: the in-surface back affordance + tap-outside leave the focused
    // thread, committing only if a reply was sent (else just defocus). Distinct
    // from _clearFeedComposerFocus, which ends the session on leaving the WHOLE
    // feed surface (tab switch / host swipe) and never commits.
    unawaited(_leaveFocusedThread(threadId));
  }

  /// Ends the focus session for [threadId] (if it is the focused card) BEFORE a
  /// commit/dismiss marks it cleared, so the removed card is never re-pinned.
  void _endFocusSessionForThread(String threadId) {
    // The swipe id is kind-qualified ('connection:'/'group:'); the focus id is
    // BARE for 1:1 + connection cards. Normalize so a focused CONNECTION card's
    // commit/dismiss actually clears focus + pin — otherwise the just-cleared
    // card is re-pinned by the store (violating "unpin before clear").
    final focusKey = threadId.startsWith('connection:')
        ? threadId.substring('connection:'.length)
        : threadId;
    if (_focusedId != focusKey) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _focusedId = null;
      _feedSessionOutgoing.remove(focusKey);
    });
    _feedStore.setPinnedThread(null);
  }

  void _onFeedComposerDraftChanged(String threadId, String text) {
    if (text.isEmpty) {
      _draftTexts.remove(threadId);
    } else {
      _draftTexts[threadId] = text;
    }
  }

  /// 134-P5 (TC-22): append-stay send from the shared composer. Records the
  /// outgoing reply so the focused card renders a new green bubble immediately
  /// and KEEPS focus, then routes to the underlying 1:1/group send. A failed or
  /// stuck send marks the reply `failed` (NOT removed) so a "tap to retry"
  /// affordance persists (never-silent send, TC-30).
  Future<void> _onFeedComposerSend(String threadId, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final reply = FeedSessionReply(messageId: _uuid.v4(), text: trimmed);
    _appendSessionOutgoing(threadId, reply);
    emitFlowEvent(
      layer: 'FL',
      event: 'FEED_SEND_APPEND',
      details: {'threadId': threadId},
    );
    await _dispatchFeedComposerSend(threadId, reply);
  }

  void _appendSessionOutgoing(String threadId, FeedSessionReply reply) {
    final list = _feedSessionOutgoing.putIfAbsent(threadId, () => []);
    list.add(reply);
    if (mounted) setState(() {});
  }

  void _markSessionOutgoingFailed(String threadId, String messageId) {
    final list = _feedSessionOutgoing[threadId];
    if (list == null) return;
    final idx = list.indexWhere((r) => r.messageId == messageId);
    if (idx < 0) return;
    list[idx] = list[idx].copyWith(failed: true);
    emitFlowEvent(
      layer: 'FL',
      event: 'FEED_SEND_RETRY_SHOWN',
      details: {'threadId': threadId},
    );
    if (mounted) setState(() {});
  }

  void _clearSessionOutgoingFailed(String threadId, String messageId) {
    final list = _feedSessionOutgoing[threadId];
    if (list == null) return;
    final idx = list.indexWhere((r) => r.messageId == messageId);
    if (idx < 0) return;
    list[idx] = list[idx].copyWith(failed: false);
    if (mounted) setState(() {});
  }

  void _recordSessionOutgoingDurableAuthority(
    String threadId,
    String messageId, {
    required bool acquired,
  }) {
    final list = _feedSessionOutgoing[threadId];
    if (list == null) return;
    final idx = list.indexWhere((reply) => reply.messageId == messageId);
    if (idx < 0) return;
    final current = list[idx];
    // Once exact durable authority has been observed, absence can only mean
    // convergence elsewhere. Never downgrade that provenance to "not staged".
    if (current.hadDurableAuthority == true ||
        current.hadDurableAuthority == acquired) {
      return;
    }
    list[idx] = current.copyWith(hadDurableAuthority: acquired);
    if (mounted) setState(() {});
  }

  bool? _sessionOutgoingDurableAuthority(String threadId, String messageId) {
    final list = _feedSessionOutgoing[threadId];
    if (list == null) return null;
    final idx = list.indexWhere((reply) => reply.messageId == messageId);
    return idx < 0 ? null : list[idx].hadDurableAuthority;
  }

  void _removeSessionOutgoing(String threadId, String messageId) {
    final list = _feedSessionOutgoing[threadId];
    if (list == null) return;
    list.removeWhere((reply) => reply.messageId == messageId);
    if (list.isEmpty) _feedSessionOutgoing.remove(threadId);
    if (mounted) setState(() {});
  }

  bool _replaceSessionOutgoing(
    String threadId,
    FeedSessionReply expected,
    FeedSessionReply replacement,
  ) {
    final list = _feedSessionOutgoing[threadId];
    if (list == null) return false;
    final idx = list.indexWhere(
      (reply) => reply.messageId == expected.messageId,
    );
    if (idx < 0) return false;
    list[idx] = replacement;
    if (mounted) setState(() {});
    return true;
  }

  Future<void> _dispatchFeedComposerSend(
    String threadId,
    FeedSessionReply reply,
  ) async {
    if (threadId.startsWith('group:')) {
      final groupId = threadId.substring('group:'.length);
      final ok = await _sendGroupComposerReply(groupId, reply.text);
      if (!ok) _markSessionOutgoingFailed(threadId, reply.messageId);
      return;
    }
    // 1:1 / system letters both resolve to a contact send.
    final ok = await _sendContactComposerReply(
      threadId,
      reply.text,
      messageId: reply.messageId,
    );
    if (!ok) _markSessionOutgoingFailed(threadId, reply.messageId);
  }

  Future<bool?> _observeExactDirectTextCustody(
    String contactPeerId,
    String messageId,
  ) async {
    final messageRepository = widget.messageRepository;
    if (messageRepository is! OutgoingDirectTextInboxCustodyRepository) {
      return false;
    }
    final custodyRepository =
        messageRepository as OutgoingDirectTextInboxCustodyRepository;
    if (!custodyRepository.supportsDirectTextInboxCustody) return false;
    try {
      return await custodyRepository.loadDirectInboxCustodyForMessage(
            recipientPeerId: contactPeerId,
            messageId: messageId,
          ) !=
          null;
    } catch (_) {
      // Unknown is intentionally distinct from a positive never-staged result:
      // a retry may not mint a second identity after an authority read failed.
      return null;
    }
  }

  /// Sends a 1:1 reply for the focused composer. Returns false (so the caller
  /// can surface a retry affordance) on any failure — never silently.
  Future<bool> _sendContactComposerReply(
    String contactPeerId,
    String text, {
    required String messageId,
  }) async {
    final identity = _identity;
    if (identity == null) {
      _recordSessionOutgoingDurableAuthority(
        contactPeerId,
        messageId,
        acquired: false,
      );
      return false;
    }
    final sanitizedText = sanitizeMessageText(text);
    String? bgTaskId;
    ConversationMessage? optimisticMessage;
    var custodyStageCommitted = false;
    var sendUseCaseInvoked = false;
    try {
      final contact = await widget.contactRepository.getContact(contactPeerId);
      if (contact == null || !mounted) {
        if (mounted) {
          _recordSessionOutgoingDurableAuthority(
            contactPeerId,
            messageId,
            acquired: false,
          );
        }
        return false;
      }

      final timestamp = DateTime.now().toUtc().toIso8601String();
      optimisticMessage = ConversationMessage(
        id: messageId,
        contactPeerId: contactPeerId,
        senderPeerId: identity.peerId,
        text: sanitizedText,
        timestamp: timestamp,
        status: 'sending',
        isIncoming: false,
        createdAt: timestamp,
      );

      bgTaskId = await callBgBegin(widget.bridge);
      sendUseCaseInvoked = true;
      final (result, message) = await sendChatMessage(
        p2pService: widget.p2pService,
        messageRepo: widget.messageRepository,
        targetPeerId: contactPeerId,
        text: sanitizedText,
        senderPeerId: identity.peerId,
        senderUsername: identity.username,
        messageId: optimisticMessage.id,
        preassignedMessageIdIsFresh: true,
        timestamp: optimisticMessage.timestamp,
        bridge: widget.bridge,
        recipientMlKemPublicKey: contact.mlKemPublicKey,
        directEventFanout:
            widget.directRouteAuthority.resolvedDirectEventFanout,
        transportMetrics: widget.transportMetrics,
        onDirectTextCustodyStaged: (stagedMessageId) {
          if (stagedMessageId != messageId) return;
          custodyStageCommitted = true;
          if (mounted) {
            _recordSessionOutgoingDurableAuthority(
              contactPeerId,
              messageId,
              acquired: true,
            );
          }
        },
      );
      final observedCustody = message == null && !custodyStageCommitted
          ? await _observeExactDirectTextCustody(contactPeerId, messageId)
          : null;
      if (!mounted) return false;

      if (message != null || observedCustody == true) {
        _recordSessionOutgoingDurableAuthority(
          contactPeerId,
          messageId,
          acquired: true,
        );
      } else if (!custodyStageCommitted &&
          observedCustody == false &&
          result != SendChatMessageResult.success) {
        _recordSessionOutgoingDurableAuthority(
          contactPeerId,
          messageId,
          acquired: false,
        );
      }

      if (result == SendChatMessageResult.success) {
        // B5: do NOT mark the conversation read on send — the incoming bubbles
        // must stay visible the whole time the user is replying. Read-marking
        // (and card removal) is deferred to leave-thread (see
        // _leaveFocusedThread / _onSwipeCommit, 134 REG-INV3).
        //
        // 160 B5: merge the held optimistic outgoing IN MEMORY (no full DB
        // re-read) so the green bubble appears immediately; mirrors the
        // incoming/status-flip merge and dedupes by id.
        if (message == null) {
          // Transport may succeed after the independently removable local
          // projection loses its race. Keep exact custody, but never resurrect
          // the optimistic snapshot as UI authority.
          _removeSessionOutgoing(contactPeerId, optimisticMessage.id);
        } else {
          _mergeOutgoingContactMessageIntoFeed(contact, message);
        }
        await _loadTotalUnreadCount();
        return true;
      }
      // Persist the failure so the optimistic bubble survives a rebuild.
      if (message == null) {
        await widget.messageRepository.conditionalTransitionStatus(
          optimisticMessage.id,
          fromStatus: 'sending',
          toStatus: 'failed',
        );
      }
      return false;
    } catch (e) {
      final observedCustody = custodyStageCommitted
          ? true
          : sendUseCaseInvoked
          ? await _observeExactDirectTextCustody(contactPeerId, messageId)
          : false;
      if (mounted && observedCustody == true) {
        _recordSessionOutgoingDurableAuthority(
          contactPeerId,
          messageId,
          acquired: true,
        );
      } else if (mounted && !sendUseCaseInvoked) {
        // Nothing capable of staging this fresh authority was invoked. This
        // positive pre-stage boundary permits one later retry to mint a new
        // identity. Once the send use case starts, an absent row is ambiguous
        // (a competing drain may already have retired it), so it stays unknown.
        _recordSessionOutgoingDurableAuthority(
          contactPeerId,
          messageId,
          acquired: false,
        );
      }
      if (optimisticMessage != null) {
        try {
          await widget.messageRepository.conditionalTransitionStatus(
            optimisticMessage.id,
            fromStatus: 'sending',
            toStatus: 'failed',
          );
        } catch (_) {
          // A persistence failure remains retryable through the next recovery
          // pass; never replace a stronger concurrent status here.
        }
      }
      emitFlowEvent(
        layer: 'FL',
        event: 'FEED_FL_COMPOSER_SEND_ERROR',
        details: {'errorType': e.runtimeType.toString()},
      );
      return false;
    } finally {
      await callBgEnd(widget.bridge, bgTaskId);
    }
  }

  /// Retries a feed-session reply without ever re-minting an old authority.
  ///
  /// A committed failed projection goes through the shared failed-message path.
  /// If its projection disappeared while exact v108 custody survived, that
  /// immutable row is drained directly. If either authority was observed
  /// earlier and both are now absent, another owner already converged it and
  /// the session bubble is dismissed. A fresh id is minted only after positive
  /// evidence that the prior attempt never acquired durable authority.
  Future<({bool ok, String messageId})> _retryContactComposerReply(
    String contactPeerId,
    FeedSessionReply reply,
  ) async {
    try {
      final existing = await widget.messageRepository.getMessage(
        reply.messageId,
      );
      if (existing == null) {
        final messageRepository = widget.messageRepository;
        if (messageRepository is OutgoingDirectTextInboxCustodyRepository) {
          final custodyRepository =
              messageRepository as OutgoingDirectTextInboxCustodyRepository;
          final observedCustody = await custodyRepository
              .loadDirectInboxCustodyForMessage(
                recipientPeerId: contactPeerId,
                messageId: reply.messageId,
              );
          if (observedCustody != null) {
            _recordSessionOutgoingDurableAuthority(
              contactPeerId,
              reply.messageId,
              acquired: true,
            );
          }
          final ackCustodyStore = widget.p2pService is AckOrExpiryInboxStore
              ? widget.p2pService as AckOrExpiryInboxStore
              : null;
          Future<InboxStoreOutcome> storeExactCustody(
            String toPeerId,
            String envelope, {
            required AckCustodyKind custodyKind,
            int? timeoutMs,
          }) async {
            if (ackCustodyStore != null) {
              return ackCustodyStore.storeInAckCustodyInboxDetailed(
                toPeerId,
                envelope,
                custodyKind: custodyKind,
                timeoutMs: timeoutMs,
              );
            }
            return const InboxStoreOutcome(
              status: InboxStoreStatus.failed,
              errorCode: 'ACK_OR_EXPIRY_STORE_UNAVAILABLE',
            );
          }

          if (observedCustody != null) {
            final custodyAttempt =
                await drainDirectInboxCustodyOutboxForMessage(
                  custodyRepository: custodyRepository,
                  storeInAckCustodyInboxDetailed: storeExactCustody,
                  storeInMediaExpiryBoundedInboxDetailed:
                      widget.p2pService is MediaExpiryBoundedInboxStore
                      ? (widget.p2pService as MediaExpiryBoundedInboxStore)
                            .storeInMediaExpiryBoundedInboxDetailed
                      : null,
                  recipientPeerId: contactPeerId,
                  messageId: reply.messageId,
                );
            if (custodyAttempt.found) {
              if (custodyAttempt.completed) {
                _removeSessionOutgoing(contactPeerId, reply.messageId);
              }
              return (ok: custodyAttempt.completed, messageId: reply.messageId);
            }
          }
        }

        final durableAuthority =
            _sessionOutgoingDurableAuthority(contactPeerId, reply.messageId) ??
            reply.hadDurableAuthority;
        if (durableAuthority == true) {
          _removeSessionOutgoing(contactPeerId, reply.messageId);
          return (ok: true, messageId: reply.messageId);
        }
        if (durableAuthority != false) {
          return (ok: false, messageId: reply.messageId);
        }

        final replacement = FeedSessionReply(
          messageId: _uuid.v4(),
          text: reply.text,
        );
        if (!_replaceSessionOutgoing(contactPeerId, reply, replacement)) {
          return (ok: false, messageId: reply.messageId);
        }
        final sent = await _sendContactComposerReply(
          contactPeerId,
          reply.text,
          messageId: replacement.messageId,
        );
        return (ok: sent, messageId: replacement.messageId);
      }
      if (existing.isIncoming || existing.contactPeerId != contactPeerId) {
        return (ok: false, messageId: reply.messageId);
      }
      _recordSessionOutgoingDurableAuthority(
        contactPeerId,
        reply.messageId,
        acquired: true,
      );
      if (existing.status != 'failed') {
        final accepted = const <String>{
          'sent',
          'inboxed',
          'delivered',
        }.contains(existing.status);
        return (ok: accepted, messageId: reply.messageId);
      }

      String? bgTaskId;
      try {
        bgTaskId = await callBgBegin(widget.bridge);
        final retried = await retryFailedMessage(
          messageId: reply.messageId,
          messageRepo: widget.messageRepository,
          identityRepo: widget.repository,
          contactRepo: widget.contactRepository,
          p2pService: widget.p2pService,
          bridge: widget.bridge,
          mediaAttachmentRepo: widget.mediaAttachmentRepository,
          mediaFileManager: widget.mediaFileManager,
        );
        if (retried <= 0 || !mounted) {
          return (ok: false, messageId: reply.messageId);
        }

        final authoritative = await widget.messageRepository.getMessage(
          reply.messageId,
        );
        final contact = await widget.contactRepository.getContact(
          contactPeerId,
        );
        if (authoritative != null && contact != null && mounted) {
          _mergeOutgoingContactMessageIntoFeed(contact, authoritative);
        } else if (authoritative == null) {
          _removeSessionOutgoing(contactPeerId, reply.messageId);
        }
        await _loadTotalUnreadCount();
        return (ok: true, messageId: reply.messageId);
      } finally {
        await callBgEnd(widget.bridge, bgTaskId);
      }
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'FEED_FL_COMPOSER_RETRY_ERROR',
        details: {'errorType': error.runtimeType.toString()},
      );
      return (ok: false, messageId: reply.messageId);
    }
  }

  /// Sends a group reply for the focused composer (Decision G: routed by group
  /// id, never a sender run peerId). Returns false on any failure.
  Future<bool> _sendGroupComposerReply(String groupId, String text) async {
    final identity = _identity;
    final groupRepo = widget.groupRepository;
    final msgRepo = widget.groupMessageRepository;
    if (identity == null || groupRepo == null || msgRepo == null) return false;
    String? bgTaskId;
    try {
      bgTaskId = await callBgBegin(widget.bridge);
      final senderDeviceId = _currentSenderDeviceId;
      final (result, message) = await sendGroupMessage(
        bridge: widget.bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: groupId,
        text: text,
        senderPeerId: identity.peerId,
        senderPublicKey: identity.publicKey,
        senderPrivateKey: identity.privateKey,
        senderUsername: identity.username,
        senderDeviceId: senderDeviceId,
        senderTransportPeerId: senderDeviceId,
        inviteDeliveryAttemptRepo: widget.groupInviteDeliveryAttemptRepository,
      );
      if (!mounted) return false;
      // 210b: queuedOffline is durably accepted (self-healing 'queued_offline'
      // row, repush lane settles it on reconnect) — treating it as a failure
      // here would show a false red retry AND a manual retry would mint a
      // duplicate row (this path sends without a messageId, so the id-reuse
      // whitelist can never match the original).
      if (result == SendGroupMessageResult.success ||
          result == SendGroupMessageResult.successNoPeers ||
          result == SendGroupMessageResult.queuedOffline) {
        // B5: defer read-marking to leave-thread (symmetric with the 1:1 path)
        // — the incoming run must stay visible while replying.
        await _refreshGroupFeedItem(groupId);
        await _loadTotalUnreadCount();
        return true;
      }
      return false;
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'FEED_FL_GROUP_COMPOSER_SEND_ERROR',
        details: {'errorType': e.runtimeType.toString()},
      );
      return false;
    } finally {
      await callBgEnd(widget.bridge, bgTaskId);
    }
  }

  /// 134-P5 (TC-30): re-invoke the send for a failed/pending session reply.
  Future<void> _onRetrySend(String threadId, FeedSessionReply reply) async {
    _clearSessionOutgoingFailed(threadId, reply.messageId);
    var authorityId = reply.messageId;
    late final bool ok;
    if (threadId.startsWith('group:')) {
      ok = await _sendGroupComposerReply(
        threadId.substring('group:'.length),
        reply.text,
      );
    } else {
      final result = await _retryContactComposerReply(threadId, reply);
      ok = result.ok;
      authorityId = result.messageId;
    }
    if (!ok) _markSessionOutgoingFailed(threadId, authorityId);
  }

  /// Opens the full conversation for a focused thread id (1:1 / system → the
  /// contact conversation; group routing is handled separately via onGroupTap).
  void _onOpenFullConversation(String contactPeerId) {
    _onReplyToMessage(contactPeerId);
  }

  // ── 134-P5: swipe contract (P6 wires the gestures to these) ───────────────

  /// 135 B2/B4/B5: the unified leave-thread handler. The back chevron, the
  /// right-swipe, and the in-surface tap-outside ALL route here. Captures
  /// whether ANY reply was sent during this focus session BEFORE the session is
  /// cleared (order trap); if a reply was sent it COMMITS (removes the card and
  /// marks the conversation read), otherwise it simply DEFOCUSES and the card
  /// stays. Sending alone never commits/reads — only leaving WITH a reply does.
  Future<void> _leaveFocusedThread(String threadId) async {
    // The swipe id is kind-qualified ('connection:'/'group:'); the focus id and
    // the outgoing session map are keyed by the BARE id for 1:1 + connection
    // cards. Strip the prefix so repliesSent reads the right session — and
    // capture it BEFORE _endFocusSessionForThread clears _feedSessionOutgoing.
    final focusKey = threadId.startsWith('connection:')
        ? threadId.substring('connection:'.length)
        : threadId;
    final repliesSent = _feedSessionOutgoing[focusKey]?.isNotEmpty ?? false;

    _endFocusSessionForThread(threadId);

    // Leave-WITHOUT-reply: return to the feed, the card stays, nothing cleared.
    if (!repliesSent) return;

    // Leave-WITH-reply: commit — remove the card and mark the thread read.
    final ms = DateTime.now().millisecondsSinceEpoch;
    final (kind, id) = _clearedKeyForThreadId(threadId);
    _feedStore.markClearedLocally(kind, id, ms);
    emitFlowEvent(
      layer: 'FL',
      event: 'FEED_CLEAR_COMMIT',
      details: {'kind': kind},
    );
    await widget.feedClearedRepository.markCleared(
      kind,
      id,
      ms,
      markRead: true,
    );
    // INV-3: commit marks the underlying conversation READ (not just cleared)
    // and refreshes the app-wide unread badge. (The cleared row only hides the
    // card; without this the thread stays unread in the DB and the badge stays
    // elevated.) A 'connection' letter has no incoming messages to read-mark.
    if (kind == feedThreadKindGroup) {
      await widget.groupMessageRepository?.markAsRead(id);
    } else if (kind == feedThreadKindContact) {
      await markConversationRead(
        messageRepo: widget.messageRepository,
        contactPeerId: id,
      );
    }
    if (mounted) await _loadTotalUnreadCount();
  }

  Future<void> _onSwipeDismiss(String threadId) async {
    _endFocusSessionForThread(threadId);
    final ms = DateTime.now().millisecondsSinceEpoch;
    final (kind, id) = _clearedKeyForThreadId(threadId);
    _feedStore.markClearedLocally(kind, id, ms);
    emitFlowEvent(
      layer: 'FL',
      event: 'FEED_CLEAR_DISMISS',
      details: {'kind': kind},
    );
    await widget.feedClearedRepository.markCleared(
      kind,
      id,
      ms,
      markRead: false,
    );
  }

  Future<void> _onUndoDismiss(String threadId) async {
    final (kind, id) = _clearedKeyForThreadId(threadId);
    _feedStore.clearClearedLocally(kind, id);
    emitFlowEvent(
      layer: 'FL',
      event: 'FEED_CLEAR_UNDO',
      details: {'kind': kind},
    );
    await widget.feedClearedRepository.clearCleared(kind, id);
  }

  /// 134-P6 gesture arena (TC-35): a card-level swipe toggles the host gate so
  /// the screen-level Feed↔Orbit host swipe yields the gesture while live. The
  /// `|| _feedCardSwipeActive` bail in `_onHostPointerMove` is the sole guard —
  /// the host neither resolves nor translates while a card swipe owns the drag.
  void _onCardSwipeActive(bool active) {
    if (_feedCardSwipeActive == active) return;
    _feedCardSwipeActive = active;
  }

  /// Maps a swipe/clear thread id to a (kind, id) cleared-watermark key.
  ///
  /// 134-P6: the id is kind-qualified by the swipe call site — `group:<id>` for
  /// groups, `connection:<peerId>` for a "new connection" system card, and a
  /// bare peerId for a 1:1 contact thread. A contact and its connection card
  /// share the same peerId, so the explicit `connection:` prefix is what keeps
  /// a 1:1 dismiss from clearing the connection row instead (and vice-versa).
  (String, String) _clearedKeyForThreadId(String threadId) {
    if (threadId.startsWith('group:')) {
      return (feedThreadKindGroup, threadId.substring('group:'.length));
    }
    if (threadId.startsWith('connection:')) {
      return (
        feedThreadKindConnection,
        threadId.substring('connection:'.length),
      );
    }
    return (feedThreadKindContact, threadId);
  }

  void _ensureOrbitHostMounted() {
    if (_hasMountedOrbitHost || !mounted) {
      return;
    }
    setState(() {
      _hasMountedOrbitHost = true;
    });
  }

  void _animateHostTo(double target) {
    final normalizedTarget = target.clamp(0.0, 1.0);
    if ((_hostSwipeController.value - normalizedTarget).abs() < 0.0001) {
      _hostSwipeController.value = normalizedTarget;
      return;
    }

    _hostSwipeController.stop();
    _hostSwipeController.animateTo(
      normalizedTarget,
      duration: _hostSwipeSettleDuration,
      curve: Curves.easeOutCubic,
    );
  }

  void _registerOrbitEmbeddedExitAction(VoidCallback? action) {
    _orbitEmbeddedExitAction = action;
  }

  void _onOrbitRowActionOpenChanged(bool isOpen) {
    _orbitRowActionOpen = isOpen;
  }

  void _onOrbitEditSessionActiveChanged(bool active) {
    _orbitEditSessionActive = active;
  }

  void _resetHostSwipeTracking() {
    _hostSwipePointer = null;
    _hostSwipeStartPosition = null;
    _hostSwipeStartTab = null;
    _hostSwipeResolved = false;
    _hostSwipeClaimed = false;
    _hostSwipeVelocityTracker = null;
  }

  void _onHostPointerDown(PointerDownEvent event) {
    if (_hostSwipePointer != null) {
      return;
    }

    _hostSwipePointer = event.pointer;
    _hostSwipeStartPosition = event.position;
    _hostSwipeStartTab = _activeTab;
    _hostSwipeResolved = false;
    _hostSwipeClaimed = false;
    _hostSwipeVelocityTracker = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.position);
  }

  void _onHostPointerMove(PointerMoveEvent event) {
    if (event.pointer != _hostSwipePointer || _hostSwipeStartPosition == null) {
      return;
    }

    _hostSwipeVelocityTracker?.addPosition(event.timeStamp, event.position);
    final totalDelta = event.position - _hostSwipeStartPosition!;
    if (!_hostSwipeResolved) {
      if (totalDelta.distance < _hostSwipeDecisionThreshold) {
        return;
      }

      _hostSwipeResolved = true;
      if (totalDelta.dx.abs() <= totalDelta.dy.abs()) {
        return;
      }

      final startingTab = _hostSwipeStartTab ?? _activeTab;
      final movingToOrbit =
          startingTab == AppShellTab.feed && totalDelta.dx < 0;
      final movingToFeed =
          startingTab == AppShellTab.orbit && totalDelta.dx > 0;
      final blockedByOrbitRow =
          startingTab == AppShellTab.orbit && _orbitRowActionOpen;
      // 198 (INV-8): an active Orbit sculpt edit session owns the horizontal
      // gesture on the orbit tab — the host yields so a handle drag can't slide
      // to Feed mid-sculpt.
      final blockedByOrbitEdit =
          startingTab == AppShellTab.orbit && _orbitEditSessionActive;
      // 134-P6 (TC-35): a live card swipe owns the horizontal gesture — the host
      // yields (mirror the blockedByOrbitRow bail).
      if ((!movingToOrbit && !movingToFeed) ||
          blockedByOrbitRow ||
          blockedByOrbitEdit ||
          _feedCardSwipeActive) {
        return;
      }

      _hostSwipeClaimed = true;
      if (startingTab == AppShellTab.feed) {
        _ensureOrbitHostMounted();
        _clearFeedComposerFocus();
      }
    }

    if (!_hostSwipeClaimed || _hostViewportWidth <= 0) {
      return;
    }

    final startingTab = _hostSwipeStartTab ?? _activeTab;
    final traveledDistance = switch (startingTab) {
      AppShellTab.feed => (-totalDelta.dx).clamp(0.0, _hostViewportWidth),
      AppShellTab.orbit => totalDelta.dx.clamp(0.0, _hostViewportWidth),
      _ => 0.0,
    };
    final progress = traveledDistance / _hostViewportWidth;

    _hostSwipeController.stop();
    _hostSwipeController.value = switch (startingTab) {
      AppShellTab.feed => progress,
      AppShellTab.orbit => 1.0 - progress,
      _ => _hostSwipeController.value,
    };
  }

  void _finishHostSwipe() {
    if (!_hostSwipeClaimed) {
      _resetHostSwipeTracking();
      return;
    }

    final velocity =
        _hostSwipeVelocityTracker?.getVelocity().pixelsPerSecond.dx ?? 0.0;
    final startingTab = _hostSwipeStartTab ?? _activeTab;
    final progressTowardTarget = switch (startingTab) {
      AppShellTab.feed => _hostSwipeController.value,
      AppShellTab.orbit => 1.0 - _hostSwipeController.value,
      _ => 0.0,
    };
    final shouldComplete =
        progressTowardTarget >= _hostSwipeCompletionThreshold ||
        (startingTab == AppShellTab.feed &&
            velocity <= -_hostSwipeVelocityThreshold) ||
        (startingTab == AppShellTab.orbit &&
            velocity >= _hostSwipeVelocityThreshold);

    _resetHostSwipeTracking();

    if (!shouldComplete) {
      _animateHostTo(startingTab == AppShellTab.orbit ? 1.0 : 0.0);
      return;
    }

    if (startingTab == AppShellTab.feed) {
      widget.appShellController.switchTo(AppShellTab.orbit);
      return;
    }

    final orbitExitAction = _orbitEmbeddedExitAction;
    if (orbitExitAction != null) {
      orbitExitAction();
      return;
    }
    widget.appShellController.switchTo(AppShellTab.feed);
  }

  void _onHostPointerUp(PointerUpEvent event) {
    if (event.pointer != _hostSwipePointer) {
      return;
    }
    _hostSwipeVelocityTracker?.addPosition(event.timeStamp, event.position);
    _finishHostSwipe();
  }

  void _onHostPointerCancel(PointerCancelEvent event) {
    if (event.pointer != _hostSwipePointer) {
      return;
    }

    final startingTab = _hostSwipeStartTab ?? _activeTab;
    final claimed = _hostSwipeClaimed;
    _resetHostSwipeTracking();
    if (claimed) {
      _animateHostTo(startingTab == AppShellTab.orbit ? 1.0 : 0.0);
    }
  }

  void _onShellChanged() {
    if (!mounted) {
      return;
    }
    // 206: Settings (opened from ANY entry point now — including the Orbit
    // center avatar) pushes identity/quality changes passively via the shared
    // controller, replacing the removed Feed-header `.then` reloads.
    final changeKind = widget.appShellController.lastChangeKind;
    if (changeKind == AppShellChangeKind.identity) {
      unawaited(_loadIdentity());
      return;
    }
    if (changeKind == AppShellChangeKind.mediaQuality) {
      unawaited(_loadQualityPreference());
      unawaited(_loadVideoQualityPreference());
      return;
    }
    // 163 (navigation-hangs-2): a background-only change must still rebuild so
    // the new BackgroundPreference reaches the panes (recolor needs the rebuild
    // under minimal scope), but it must NOT run the tab-change side-effects
    // (composer focus clear, orbit-host latch, host slide). Only a tab change
    // runs those.
    if (widget.appShellController.lastChangeKind ==
        AppShellChangeKind.background) {
      setState(() {});
      return;
    }
    final activeTab = widget.appShellController.activeTab;
    if (activeTab != AppShellTab.feed) {
      _clearFeedComposerFocus(notify: false);
    }
    setState(() {
      _hasMountedOrbitHost =
          _hasMountedOrbitHost || activeTab == AppShellTab.orbit;
    });
    _animateHostTo(activeTab == AppShellTab.orbit ? 1.0 : 0.0);
  }

  void _onSwitchView(String tab) {
    widget.appShellController.switchTo(tab);
  }

  void _onOrbitEmbeddedExit(FeedRouteChanges? changes) {
    unawaited(_applyRouteChanges(changes));
  }

  Widget _buildOrbitHost() {
    return OrbitWired(
      directRouteAuthority: widget.directRouteAuthority,
      callActivitySource: widget.orbitCallActivitySource,
      resolveCallWakeHandle: widget.resolveCallWakeHandle,
      onCallWakeHandleDistributed: widget.onCallWakeHandleDistributed,
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
      groupReactionReplayOutboxRepository:
          widget.groupReactionReplayOutboxRepository,
      groupMessageListener: widget.groupMessageListener,
      groupMediaDownloadCoordinator: widget.groupMediaDownloadCoordinator,
      groupInviteListener: widget.groupInviteListener,
      waitForGroupMembershipUpdateIdle: widget.waitForGroupMembershipUpdateIdle,
      groupConversationTracker: widget.groupConversationTracker,
      introductionRepository: widget.introductionRepository,
      introductionListener: widget.introductionListener,
      appShellController: widget.appShellController,
      feedUnreadCountListenable: _totalUnreadCountNotifier,
      // Orbit is the chromeless home landing: suppress its center Feed/Orbit
      // toggle bar. Feed stays reachable via the host swipe and its own toggle
      // (Feed pane keeps its nav bar). Flip to false to revive the toggle on
      // Orbit without any re-plumbing.
      hideShellNav: true,
      pendingPostTargetStore: widget.pendingPostTargetStore,
      postsPrivacySettingsRepository: widget.postsPrivacySettingsRepository,
      externalRouteChangesListenable: _mountedOrbitRouteChangesNotifier,
      initialFilterTab: null,
      onEmbeddedExit: _onOrbitEmbeddedExit,
      onEmbeddedExitActionChanged: _registerOrbitEmbeddedExitAction,
      onRowActionOpenChanged: _onOrbitRowActionOpenChanged,
      onEditSessionActiveChanged: _onOrbitEditSessionActiveChanged,
      transportMetrics: widget.transportMetrics,
      accountMigrationRunTransfer: widget.accountMigrationRunTransfer,
      accountMigrationSizeGate: widget.accountMigrationSizeGate,
      // 206: the Orbit center avatar opens Settings; thread the nearby service
      // so its posts-nearby refresh is functional (not silently degraded).
      nearbyLocationService: widget.nearbyLocationService,
    );
  }

  Future<void> _onUsernameChanged(String newUsername) async {
    final identity = _identity;
    if (identity == null) return;

    final updatedIdentity = IdentityModel(
      peerId: identity.peerId,
      publicKey: identity.publicKey,
      privateKey: identity.privateKey,
      mnemonic12: identity.mnemonic12,
      mlKemPublicKey: identity.mlKemPublicKey,
      mlKemSecretKey: identity.mlKemSecretKey,
      username: newUsername,
      avatarBlob: identity.avatarBlob,
      avatarVersion: identity.avatarVersion,
      createdAt: identity.createdAt,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    );

    try {
      await widget.repository.saveIdentity(updatedIdentity);
      if (!mounted) return;

      setState(() {
        _identity = updatedIdentity;
        _username = newUsername;
      });

      emitFlowEvent(
        layer: 'FL',
        event: 'FEED_FL_USERNAME_UPDATED',
        details: {'username': newUsername},
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'FEED_FL_USERNAME_ERROR',
        details: {'error': e.toString()},
      );
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.error_update_username),
          backgroundColor: Colors.red[700],
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  void dispose() {
    widget.appShellController.removeListener(_onShellChanged);
    _requestSubscription?.cancel();
    _chatSubscription?.cancel();
    _repoChangeSubscription?.cancel();
    _conversationReadSubscription?.cancel();
    _contactUpdateSubscription?.cancel();
    _reactionSubscription?.cancel();
    _groupReactionSubscription?.cancel();
    _groupMessageSubscription?.cancel();
    _groupInviteJoinedSubscription?.cancel();
    _pendingGroupInviteSubscription?.cancel();
    _introReceivedSubscription?.cancel();
    _introStatusSubscription?.cancel();
    // 162: cancel any pending coalesce timers so a flush cannot fire after
    // unmount (no setState-after-dispose).
    for (final timer in _pendingContactFlushTimers.values) {
      timer.cancel();
    }
    _pendingContactFlushTimers.clear();
    _pendingContactFlushes.clear();
    _hostSwipeController.dispose();
    _totalUnreadCountNotifier.dispose();
    _orbitBadgeCountNotifier.dispose();
    _mountedOrbitRouteChangesNotifier.dispose();
    _reactionStore.dispose();
    _feedStore.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeTab = _activeTab;
    // 163 (navigation-hangs-2): each pane is isolated in its own RepaintBoundary
    // (built here, OUTSIDE the AnimatedBuilder.builder, so swipe identity holds)
    // to contain a rebuild/repaint of one pane from dirtying the other.
    final feedBody = RepaintBoundary(
      key: const ValueKey<String>('feed-pane-repaint-boundary'),
      child: FeedScreen(
        username: _username,
        userPeerId: _peerId,
        feedItems: _feedItems,
        feedItemsListenable: _feedStore.itemsListenable,
        feedLoaded: _feedLoaded,
        onUsernameChanged: _onUsernameChanged,
        p2pService: widget.p2pService,
        onSwitchView: _onSwitchView,
        activeTab: activeTab,
        onSendMessage: _onSendMessage,
        totalUnreadCountListenable: _totalUnreadCountNotifier,
        orbitBadgeCountListenable: _orbitBadgeCountNotifier,
        onOpenFullConversation: _onOpenFullConversation,
        onGroupTap: _onGroupTap,
        focusedId: _focusedId,
        onFocusCard: _onFocusCard,
        onClearFocus: _onClearFocus,
        onComposerSend: _onFeedComposerSend,
        onComposerDraftChanged: _onFeedComposerDraftChanged,
        sessionReplies: _feedSessionOutgoing,
        onRetrySend: _onRetrySend,
        onSwipeCommit: _leaveFocusedThread,
        onSwipeDismiss: _onSwipeDismiss,
        onUndoDismiss: _onUndoDismiss,
        onCardSwipeActive: _onCardSwipeActive,
        backgroundPreference: widget.appShellController.backgroundPreference,
      ),
    );
    final orbitBody = _hasMountedOrbitHost
        ? RepaintBoundary(
            key: const ValueKey<String>('orbit-pane-repaint-boundary'),
            child: _buildOrbitHost(),
          )
        : const SizedBox.shrink();
    final body = LayoutBuilder(
      builder: (context, constraints) {
        _hostViewportWidth = constraints.maxWidth;

        return Listener(
          key: const ValueKey<String>('feed-orbit-swipe-host'),
          behavior: HitTestBehavior.translucent,
          onPointerDown: _onHostPointerDown,
          onPointerMove: _onHostPointerMove,
          onPointerUp: _onHostPointerUp,
          onPointerCancel: _onHostPointerCancel,
          child: AnimatedBuilder(
            animation: _hostSwipeController,
            builder: (context, child) {
              final hostProgress = _hostSwipeController.value.clamp(0.0, 1.0);
              final feedOffset = -hostProgress * constraints.maxWidth;
              final orbitOffset = (1.0 - hostProgress) * constraints.maxWidth;
              // 163 (animations-repaint-2): mute the off-screen pane's tickers
              // (both ambient loops + orbit controllers) via TickerMode at rest,
              // while keeping BOTH live mid-swipe so the slide animates (drag in
              // progress OR the snap-back/settle still running).
              final midSwipe =
                  (_hostSwipePointer != null && _hostSwipeClaimed) ||
                  _hostSwipeController.isAnimating;
              final feedTickerEnabled =
                  activeTab == AppShellTab.feed || midSwipe;
              final orbitTickerEnabled =
                  activeTab == AppShellTab.orbit || midSwipe;

              return ClipRect(
                child: Stack(
                  children: [
                    TickerMode(
                      key: const ValueKey<String>('feed-pane-ticker-mode'),
                      enabled: feedTickerEnabled,
                      child: Transform.translate(
                        offset: Offset(feedOffset, 0),
                        child: SizedBox(
                          width: constraints.maxWidth,
                          height: constraints.maxHeight,
                          child: feedBody,
                        ),
                      ),
                    ),
                    if (_hasMountedOrbitHost)
                      TickerMode(
                        key: const ValueKey<String>('orbit-pane-ticker-mode'),
                        enabled: orbitTickerEnabled,
                        child: Transform.translate(
                          offset: Offset(orbitOffset, 0),
                          child: SizedBox(
                            width: constraints.maxWidth,
                            height: constraints.maxHeight,
                            child: orbitBody,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );

    return Scaffold(resizeToAvoidBottomInset: false, body: body);
  }
}

/// 162: per-contact pending state for the trailing feed-reload coalescer.
///
/// [latestMessage] drives the incremental hot path (status-flip burst).
/// [sawDestructive] / [sawDistinctIds] are sticky escalation flags (a delete/hide
/// or a second distinct id forces a full snapshot reload, which the incremental
/// single-id upsert could not represent without losing a message).
/// [sawRefreshUnread] is OR-accumulated across sources so a mixed
/// incoming+outgoing burst still recomputes the unread count exactly once.
class _PendingContactFeedFlush {
  _PendingContactFeedFlush({
    required this.latestMessage,
    required this.firstPendingId,
    required this.sawDistinctIds,
    required this.sawDestructive,
    required this.sawRefreshUnread,
  });

  ConversationMessage latestMessage;
  final String firstPendingId;
  bool sawDistinctIds;
  bool sawDestructive;
  bool sawRefreshUnread;
}
