import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/debug/transport_metrics.dart';
import 'package:flutter_app/core/media/audio_recorder_service.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_storage_manager.dart';
import 'package:flutter_app/features/conversation/domain/models/media_library.dart';
import 'package:flutter_app/features/settings/presentation/widgets/media_storage_usage_section.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/settings/application/image_quality_preference_use_cases.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_app/features/settings/domain/models/image_quality_preference.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_transfer_flow.dart';
import 'package:flutter_app/features/account_migration/application/migration_account_size_estimator.dart';
import 'package:flutter_app/features/account_migration/presentation/screens/account_migration_journey_wired.dart';
import 'package:flutter_app/features/contact_request/application/accept_and_reciprocate_use_case.dart';
import 'package:flutter_app/features/contact_request/application/accept_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contact_request/application/decline_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/contact_request/domain/repositories/contact_request_repository.dart';
import 'package:flutter_app/features/contact_profile/presentation/screens/contact_profile_screen.dart';
import 'package:flutter_app/features/contact_request/presentation/widgets/contact_request_dialog.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/mark_conversation_read_use_case.dart';
import 'package:flutter_app/features/conversation/application/reaction_listener.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/conversation/presentation/navigation/conversation_route_transition.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_wired.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/home/application/identity_avatar_resolver.dart';
import 'package:flutter_app/features/contacts/application/archive_contact_use_case.dart';
import 'package:flutter_app/features/groups/application/archive_group_use_case.dart';
import 'package:flutter_app/features/groups/application/unarchive_group_use_case.dart';
import 'package:flutter_app/features/groups/application/delete_group_and_messages_use_case.dart';
import 'package:flutter_app/features/groups/application/leave_group_use_case.dart';
import 'package:flutter_app/features/groups/application/rejoin_group_topics_use_case.dart';
import 'package:flutter_app/core/config/on_join_metadata_resync_flag.dart';
import 'package:flutter_app/features/groups/application/accept_pending_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/application/on_join_group_config_resync_use_case.dart';
import 'package:flutter_app/features/groups/application/decline_pending_group_invite_use_case.dart';
import 'package:flutter_app/features/contacts/application/block_contact_use_case.dart';
import 'package:flutter_app/features/contacts/application/delete_contact_use_case.dart';
import 'package:flutter_app/features/contacts/application/unarchive_contact_use_case.dart';
import 'package:flutter_app/features/contacts/application/unblock_contact_use_case.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/confirmation_dialog.dart';
import 'package:flutter_app/features/orbit/application/inner_circle_items.dart';
import 'package:flutter_app/features/orbit/application/load_orbit_data_use_case.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_view_mode.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/application/group_invite_listener.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_welcome_key_package.dart';
import 'package:flutter_app/features/groups/domain/models/pending_group_invite.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_history_gap_repair_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_key_repair_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_reaction_replay_outbox_repository.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/introduction/domain/repositories/introduction_repository.dart';
import 'package:flutter_app/features/introduction/domain/repositories/intro_review_seen_repository.dart';
import 'package:flutter_app/features/introduction/application/introduction_listener.dart';
import 'package:flutter_app/features/introduction/application/accept_introduction_use_case.dart';
import 'package:flutter_app/features/introduction/application/folded_introduction_response_use_case.dart';
import 'package:flutter_app/features/introduction/application/pass_introduction_use_case.dart';
import 'package:flutter_app/features/introduction/application/expire_old_introductions_use_case.dart';
import 'package:flutter_app/features/introduction/application/load_introductions_use_case.dart';
import 'package:flutter_app/features/introduction/application/unseen_review_count.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_item.dart';
import 'package:flutter_app/features/groups/presentation/screens/create_group_picker_wired.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_wired.dart';
import 'package:flutter_app/features/orbit/application/load_orbit_groups_use_case.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_group.dart';
import 'package:flutter_app/features/qr_code/presentation/screens/qr_display_wired.dart';
import 'package:flutter_app/features/qr_code/presentation/screens/qr_scanner_wired.dart';
import 'package:flutter_app/features/feed/application/app_shell_controller.dart';
import 'package:flutter_app/features/feed/data/feed_cleared_repository.dart';
import 'package:flutter_app/features/feed/domain/models/app_shell_tab.dart';
import 'package:flutter_app/features/feed/domain/models/feed_route_changes.dart';
import 'package:flutter_app/features/posts/application/nearby_location_service.dart';
import 'package:flutter_app/features/posts/application/pending_post_target_store.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';
import 'package:flutter_app/features/posts/domain/repositories/posts_privacy_settings_repository.dart';
import 'package:flutter_app/features/settings/presentation/navigation/settings_route_transition.dart';
import 'package:flutter_app/features/settings/presentation/screens/settings_wired.dart';
import 'orbit_screen.dart';

/// Wired widget connecting OrbitScreen to business logic.
///
/// Manages state, animations, streams, and DI for the Orbit feature.
class OrbitWired extends StatefulWidget {
  final IdentityRepository identityRepo;
  final ContactRepository contactRepo;
  final ContactRequestRepository contactRequestRepo;
  final ContactRequestListener contactRequestListener;
  final MessageRepository messageRepo;
  final PostRepository? postRepository;
  final MediaAttachmentRepository mediaAttachmentRepo;
  final ChatMessageListener chatMessageListener;
  final Bridge bridge;
  final P2PService p2pService;
  final MediaFileManager mediaFileManager;
  final SecureKeyStore secureKeyStore;
  final ImageProcessor imageProcessor;

  /// 135 B6: threaded through to the embedded [FeedWired] (scan → Feed handoff)
  /// AND the [QRScannerWired] it constructs, which requires it before it can
  /// navigate to the Feed after a successful contact scan.
  final FeedClearedRepository feedClearedRepository;
  final ActiveConversationTracker? conversationTracker;
  final AudioRecorderService? audioRecorderService;
  final ReactionRepository? reactionRepository;
  final ReactionListener? reactionListener;
  final GroupRepository? groupRepository;
  final GroupMessageRepository? groupMessageRepository;
  final GroupInviteDeliveryAttemptRepository?
  groupInviteDeliveryAttemptRepository;
  final GroupPendingKeyRepairRepository? groupPendingKeyRepairRepository;
  final GroupHistoryGapRepairRepository? groupHistoryGapRepairRepository;
  final GroupReactionReplayOutboxRepository?
  groupReactionReplayOutboxRepository;
  final GroupMessageListener? groupMessageListener;
  final GroupInviteListener? groupInviteListener;
  final Future<void> Function()? waitForGroupMembershipUpdateIdle;
  final ActiveConversationTracker? groupConversationTracker;
  final IntroductionRepository? introductionRepository;
  final IntroReviewSeenRepository? introReviewSeenRepository;
  final IntroductionListener? introductionListener;
  final AppShellController? appShellController;
  final ValueListenable<int>? feedUnreadCountListenable;
  final ValueListenable<FeedRouteChanges?>? externalRouteChangesListenable;
  final ValueChanged<FeedRouteChanges?>? onEmbeddedExit;
  final ValueChanged<VoidCallback?>? onEmbeddedExitActionChanged;
  final ValueChanged<bool>? onRowActionOpenChanged;

  /// 198 — bubbles the Inner-Circle edit-session active flag to the embedding
  /// host (the feed↔orbit host-swipe yield gate). Invoked on edit enter/exit.
  final ValueChanged<bool>? onEditSessionActiveChanged;
  final PendingPostTargetStore? pendingPostTargetStore;
  final PostsPrivacySettingsRepository? postsPrivacySettingsRepository;
  final String? initialFilterTab;
  final VoidCallback? debugOnHeaderBuild;
  final VoidCallback? debugOnListBuild;
  final TransportMetrics? transportMetrics;

  /// 229 — optional storage-management capability threaded into Settings'
  /// Media & storage sheet (totals/actions render only when both are set).
  final MediaStorageManager? mediaStorageManager;
  final Future<List<MediaStorageScopeOption>> Function()?
  mediaStorageScopesProvider;
  final AccountMigrationTransferRunFn? accountMigrationRunTransfer;
  final AccountMigrationSizeGate? accountMigrationSizeGate;

  /// 206 — threaded into the Settings screen opened from the center self-avatar
  /// so its posts-nearby interactive refresh is functional (not degraded).
  final NearbyLocationService? nearbyLocationService;

  /// When true, the home host renders Orbit chromeless: the center Feed/Orbit
  /// toggle bar is suppressed (Feed stays reachable via the host swipe + its own
  /// toggle). Threaded straight through to [OrbitScreen.hideShellNav]. Defaults
  /// false so every other caller / bare pump keeps the toggle.
  final bool hideShellNav;

  const OrbitWired({
    super.key,
    required this.identityRepo,
    required this.contactRepo,
    required this.contactRequestRepo,
    required this.contactRequestListener,
    required this.messageRepo,
    this.postRepository,
    required this.mediaAttachmentRepo,
    required this.chatMessageListener,
    required this.bridge,
    required this.p2pService,
    required this.mediaFileManager,
    required this.secureKeyStore,
    required this.imageProcessor,
    required this.feedClearedRepository,
    this.conversationTracker,
    this.audioRecorderService,
    this.reactionRepository,
    this.reactionListener,
    this.groupRepository,
    this.groupMessageRepository,
    this.groupInviteDeliveryAttemptRepository,
    this.groupPendingKeyRepairRepository,
    this.groupHistoryGapRepairRepository,
    this.groupReactionReplayOutboxRepository,
    this.groupMessageListener,
    this.groupInviteListener,
    this.waitForGroupMembershipUpdateIdle,
    this.groupConversationTracker,
    this.introductionRepository,
    this.introReviewSeenRepository,
    this.introductionListener,
    this.appShellController,
    this.feedUnreadCountListenable,
    this.externalRouteChangesListenable,
    this.onEmbeddedExit,
    this.onEmbeddedExitActionChanged,
    this.onRowActionOpenChanged,
    this.onEditSessionActiveChanged,
    this.pendingPostTargetStore,
    this.postsPrivacySettingsRepository,
    this.initialFilterTab,
    this.debugOnHeaderBuild,
    this.debugOnListBuild,
    this.transportMetrics,
    this.mediaStorageManager,
    this.mediaStorageScopesProvider,
    this.accountMigrationRunTransfer,
    this.accountMigrationSizeGate,
    this.nearbyLocationService,
    this.hideShellNav = false,
  });

  @override
  State<OrbitWired> createState() => _OrbitWiredState();
}

class _OrbitWiredState extends State<OrbitWired> with TickerProviderStateMixin {
  static const _acceptRecoveryRetryCount = 5;
  static const _acceptRecoveryRetryDelay = Duration(milliseconds: 500);

  IdentityModel? _identity;
  Uint8List? _avatarBytes;
  List<OrbitFriend> _activeFriends = [];
  List<OrbitFriend> _archivedFriends = [];
  List<OrbitGroup> _activeGroups = [];
  List<OrbitGroup> _archivedGroups = [];
  bool _activeFriendsLoaded = false;
  bool _archivedFriendsLoaded = false;
  bool _activeGroupsLoaded = false;
  bool _archivedGroupsLoaded = false;
  late String _filterTab;
  // 193: which surface Orbit shows. Reset to innerCircle on every entry (not
  // persisted). Seeded in initState; flipped by [_onToggleView]; reset by
  // [_resetToInnerCircleView] on the Feed→Orbit rising edge.
  late OrbitViewMode _viewMode;
  bool _searchActive = false;
  String _searchQuery = '';

  // 198 — bumped on the Feed→Orbit rising edge; the Inner-Circle interactive
  // surface listens and re-derives its transient state (expansion/labels/edit/
  // find) to defaults. The persisted knobs are untouched.
  final ValueNotifier<int> _innerCircleResetTick = ValueNotifier<int>(0);
  bool _isSearchTriggerVisible = true;
  final ValueNotifier<Key?> _openRowNotifier = ValueNotifier(null);
  final ValueNotifier<OrbitHeaderProjection> _headerProjectionNotifier =
      ValueNotifier<OrbitHeaderProjection>(const OrbitHeaderProjection());
  final ValueNotifier<OrbitViewProjection> _listProjectionNotifier =
      ValueNotifier<OrbitViewProjection>(const OrbitViewProjection());

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  double _lastScrollOffset = 0;

  late final AnimationController _collapseController;
  late final AnimationController _searchDockController;
  late final AnimationController _searchTriggerController;
  // 202 INV-202-5: hoisted so OrbitScreen receives the SAME animation object
  // across rebuilds. The old per-build CurvedAnimation registered a never-
  // removed status listener on each shared controller every OrbitWired build.
  late final CurvedAnimation _collapseAnimation;
  late final CurvedAnimation _searchDockAnimation;
  late final CurvedAnimation _searchTriggerAnimation;

  StreamSubscription<ConversationMessage>? _chatSubscription;
  StreamSubscription<ContactModel>? _contactUpdateSubscription;
  StreamSubscription<ContactRequestModel>? _requestSubscription;
  StreamSubscription<GroupMessage>? _groupMessageSubscription;
  StreamSubscription<GroupModel>? _groupJoinedInviteSubscription;
  StreamSubscription<PendingGroupInvite>? _pendingGroupInviteSubscription;
  StreamSubscription<IntroductionModel>? _introReceivedSubscription;
  StreamSubscription<IntroductionModel>? _introStatusSubscription;
  // 194: read-marking events (peerId) from the message repo — clears a lit
  // unread node even when the read happened on a surface with no orbit nav hook.
  StreamSubscription<String>? _readSubscription;
  ImageQualityPreference _qualityPreference = ImageQualityPreference.compressed;
  ImageQualityPreference _videoQualityPreference =
      ImageQualityPreference.compressed;
  int _introsCount = 0;
  Map<String, List<IntroductionModel>> _groupedIntros = {};
  List<FoldedIntroductionReviewItem> _foldedReviewItems = const [];
  Map<String, String> _introducerUsernames = {};
  List<PendingGroupInvite> _pendingGroupInvites = [];
  Set<String> _seenReviewKeys = const {};
  final Set<String> _processingIntroductionIds = <String>{};
  final Set<String> _processingPendingInviteIds = <String>{};
  // 153: parity with group_list — invites optimistically hidden while their
  // deferred decline commit is pending. Filtered inside
  // [_loadPendingGroupInvites] so every reactive reload respects the hide; the
  // per-invite [Timer] commits on timeout (Undo / dispose cancel it first).
  final Set<String> _optimisticallyDeclinedInviteIds = <String>{};
  final Map<String, Timer> _declineCommitTimers = <String, Timer>{};

  /// 153: captured when a decline SnackBar is shown so [dispose] can dismiss
  /// the still-visible Undo affordance even after this State is torn down.
  ScaffoldMessengerState? _declineScaffoldMessenger;
  final Set<String> _openingFriendPeerIds = <String>{};
  Set<String> _blockedPeerIds = {};
  final Set<String> _changedContactPeerIds = <String>{};
  final Set<String> _changedGroupIds = <String>{};
  bool _refreshPendingIntroductionsOnPop = false;
  int _introLoadRequestId = 0;

  static const _animCurve = Cubic(0.22, 0.61, 0.36, 1);

  /// 153: how long the "Invite declined" SnackBar offers an Undo before the
  /// decline commits irrevocably.
  static const kDeclineUndoWindow = Duration(seconds: 4);

  OrbitHeaderProjection _buildHeaderProjection() {
    return OrbitHeaderProjection(
      userPeerId: _identity?.peerId,
      userAvatarBytes: _avatarBytes,
      allFriends: List<OrbitFriend>.unmodifiable(_activeFriends),
      // 197: the Inner-Circle rings render active friends + active groups
      // interleaved by recency (blocked friends dropped by the merge; archived
      // groups already excluded from _activeGroups by the loader).
      innerItems: List<OrbitItem>.unmodifiable(
        mergeInnerCircleItems(friends: _activeFriends, groups: _activeGroups),
      ),
    );
  }

  OrbitViewProjection _buildListProjection() {
    final baseFriends = _filterTab == 'archived'
        ? _archivedFriends
        : _activeFriends;
    final displayedFriends = _searchQuery.isEmpty
        ? baseFriends
        : baseFriends
              .where(
                (friend) => friend.username.toLowerCase().contains(
                  _searchQuery.toLowerCase().trim(),
                ),
              )
              .toList(growable: false);
    final groups = _filterTab == 'archived' ? _archivedGroups : _activeGroups;

    final mergedItems = <OrbitItem>[
      ...displayedFriends.map(OrbitFriendItem.new),
      if (!_searchActive) ...groups.map(OrbitGroupItem.new),
    ]..sort((a, b) => b.sortKey.compareTo(a.sortKey));

    final showLoadingPlaceholders = switch (_filterTab) {
      'archived' => !_archivedFriendsLoaded || !_archivedGroupsLoaded,
      'intros' => false,
      _ => !_activeFriendsLoaded || !_activeGroupsLoaded,
    };

    final currentReviewKeys = _currentReviewKeys();
    final unseenReviewCount = _unseenReviewKeys(currentReviewKeys).length;

    return OrbitViewProjection(
      allFriends: List<OrbitFriend>.unmodifiable(_activeFriends),
      displayedFriends: List<OrbitFriend>.unmodifiable(displayedFriends),
      groups: List<OrbitGroup>.unmodifiable(groups),
      mergedItems: List<OrbitItem>.unmodifiable(mergedItems),
      activeCount: _activeFriends.length + _activeGroups.length,
      archivedCount: _archivedFriends.length + _archivedGroups.length,
      introCount: _introsCount,
      pendingGroupInviteCount: _pendingGroupInvites.length,
      reviewCount: _introsCount + _pendingGroupInvites.length,
      unseenReviewCount: unseenReviewCount,
      introsData: OrbitIntrosViewData(
        groupedIntros: _groupedIntros,
        foldedReviewItems: List<FoldedIntroductionReviewItem>.unmodifiable(
          _foldedReviewItems,
        ),
        introducerUsernames: _introducerUsernames,
        ownPeerId: _identity?.peerId ?? '',
        pendingGroupInvites: List<PendingGroupInvite>.unmodifiable(
          _pendingGroupInvites,
        ),
        processingIntroductionIds: _processingIntroductionIds,
        processingPendingInviteIds: _processingPendingInviteIds,
        onAccept: _onAcceptIntro,
        onPass: _onPassIntro,
        onDelete: _onDeleteIntro,
        onSendMessage: _onIntroSendMessage,
        onAcceptPendingInvite: _onAcceptPendingInvite,
        onDeclinePendingInvite: _onDeclinePendingInvite,
        blockedPeerIds: _blockedPeerIds,
      ),
      searchActive: _searchActive,
      searchQuery: _searchQuery,
      filterTab: _filterTab,
      showLoadingPlaceholders: showLoadingPlaceholders,
    );
  }

  Set<String> _currentReviewKeys() {
    return {
      for (final item in _foldedReviewItems)
        introReviewKeyForIntroTarget(item.targetPeerId),
      for (final invite in _pendingGroupInvites)
        introReviewKeyForGroupInvite(invite.groupId),
    };
  }

  Set<String> _unseenReviewKeys(Set<String> currentKeys) {
    if (widget.introReviewSeenRepository == null) {
      return currentKeys;
    }
    return computeUnseenReviewKeys(
      currentKeys: currentKeys,
      seenKeys: _seenReviewKeys,
    );
  }

  void _publishHeaderProjection() {
    _headerProjectionNotifier.value = _buildHeaderProjection();
  }

  void _publishListProjection() {
    _listProjectionNotifier.value = _buildListProjection();
  }

  void _publishAllProjections() {
    _publishHeaderProjection();
    _publishListProjection();
  }

  void _publishHostGestureContracts() {
    widget.onEmbeddedExitActionChanged?.call(
      widget.onEmbeddedExit != null ? _onClose : null,
    );
    widget.onRowActionOpenChanged?.call(_openRowNotifier.value != null);
  }

  void _onOpenRowNotifierChanged() {
    widget.onRowActionOpenChanged?.call(_openRowNotifier.value != null);
  }

  @override
  void initState() {
    super.initState();
    _filterTab = widget.initialFilterTab ?? 'all';
    // 193 design lock: a non-null initialFilterTab (intro-notification route,
    // 'intros'/'archived' harnesses) opens directly on the all-chats surface so
    // the requested tab is reachable with zero taps; otherwise default to the
    // Inner-Circle view.
    _viewMode = widget.initialFilterTab != null
        ? OrbitViewMode.allChats
        : OrbitViewMode.innerCircle;
    final hasGroupSurfaces =
        widget.groupRepository != null && widget.groupMessageRepository != null;
    _activeGroupsLoaded = !hasGroupSurfaces;
    _archivedGroupsLoaded = !hasGroupSurfaces;
    _publishAllProjections();
    _publishHostGestureContracts();
    _openRowNotifier.addListener(_onOpenRowNotifierChanged);
    widget.appShellController?.addListener(_onAppShellChanged);
    emitFlowEvent(layer: 'FL', event: 'ORBIT_FL_SCREEN_INIT', details: {});

    _collapseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 580),
      value: 1.0, // starts expanded
    );
    _searchDockController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 560),
    );
    _searchTriggerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 340),
      value: 1.0, // starts visible
    );
    _collapseAnimation =
        CurvedAnimation(parent: _collapseController, curve: _animCurve);
    _searchDockAnimation =
        CurvedAnimation(parent: _searchDockController, curve: _animCurve);
    _searchTriggerAnimation =
        CurvedAnimation(parent: _searchTriggerController, curve: Curves.ease);

    _loadIdentity();
    _loadQualityPreference();
    _loadVideoQualityPreference();
    _loadOrbitData();
    _loadGroupData();
    _loadIntroReviewSeenKeys();
    _loadPendingGroupInvites();
    _loadIntroductions();
    _startListeningForChatMessages();
    _startListeningForContactUpdates();
    _startListeningForReadEvents();
    _startListeningForContactRequests();
    _startListeningForGroupMessages();
    _startListeningForPendingGroupInvites();
    _startListeningForIntroductions();
    _wasOrbitActive = _isOrbitActive;
    _attachExternalRouteChangesListenable(
      widget.externalRouteChangesListenable,
    );
    _scrollController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant OrbitWired oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.onEmbeddedExit != widget.onEmbeddedExit ||
        oldWidget.onEmbeddedExitActionChanged !=
            widget.onEmbeddedExitActionChanged ||
        oldWidget.onRowActionOpenChanged != widget.onRowActionOpenChanged) {
      _publishHostGestureContracts();
    }
    if (oldWidget.externalRouteChangesListenable !=
        widget.externalRouteChangesListenable) {
      _detachExternalRouteChangesListenable(
        oldWidget.externalRouteChangesListenable,
      );
      _attachExternalRouteChangesListenable(
        widget.externalRouteChangesListenable,
      );
    }
    if (oldWidget.appShellController != widget.appShellController) {
      oldWidget.appShellController?.removeListener(_onAppShellChanged);
      widget.appShellController?.addListener(_onAppShellChanged);
    }
  }

  // 163 (reactive-streams-3): a null appShellController means a standalone Orbit
  // (no shell to be off-screen behind) → always active. Otherwise Orbit is
  // active only when it is the selected shell tab.
  bool get _isOrbitActive =>
      widget.appShellController == null ||
      widget.appShellController!.activeTab == AppShellTab.orbit;

  // Per-reason dirty buckets buffer the work that gated off-screen orbit
  // subscriptions would have done, so re-activation replays exactly one targeted
  // refresh per reason (pause/dirty-flag, never cancel — preserves 131-class
  // live-update delivery). Contact-requests are NEVER buffered (they stay live).
  final Set<String> _dirtyFriendPeerIds = {};
  final Set<String> _dirtyGroupIds = {};

  // 202: trailing-flush refresh coalescer (feed 162 precedent). Burst sources
  // (the chat / group message streams + the Feed→Orbit dirty replay) enqueue
  // here; a same-key burst inside the 32ms window dedupes to ONE snapshot load
  // (+ ONE rejoin-states load per group) and ONE projection publish per flush.
  final Set<String> _pendingFriendRefreshPeerIds = {};
  final Set<String> _pendingGroupRefreshGroupIds = {};
  Timer? _orbitRefreshCoalesceTimer;
  static const Duration _orbitRefreshCoalesceWindow =
      Duration(milliseconds: 32);

  bool _introsDirty = false;
  bool _invitesDirty = false;
  bool _wasOrbitActive = true;

  // 206 — single-flight latch for the center-avatar Settings route.
  bool _settingsRouteActive = false;

  void _onAppShellChanged() {
    if (!mounted) {
      return;
    }
    // 206: a self-identity change (username/avatar saved in Settings) reloads
    // the center avatar. This is the SINGLE refresh mechanism — no
    // `.then(_loadIdentity)` on the settings push (dual mechanisms mask a
    // mutation revert — the INV-203-1 lesson). Orbit renders no self username,
    // so this runs purely for avatar-bytes correctness on a photo change.
    if (widget.appShellController?.lastChangeKind ==
        AppShellChangeKind.identity) {
      _loadIdentity();
      return;
    }
    final isActive = _isOrbitActive;
    if (isActive && !_wasOrbitActive) {
      // 193: every entry into Orbit resets to the Inner-Circle view (no
      // persistence). This runs on the actual inactive→active rising edge only,
      // so a background-kind notify while Orbit is active cannot reset it. Order
      // lock: reset must NOT short-circuit the dirty replay (cat.22).
      _resetToInnerCircleView();
      _replayDirtyOrbitWork();
    }
    _wasOrbitActive = isActive;
    setState(() {});
  }

  // 193: reset the view surface on every Orbit re-activation. Force-closes
  // search so its dock/trigger can't linger over the Inner-Circle surface. The
  // filter tab is deliberately preserved (locked asymmetry — cat.13).
  void _resetToInnerCircleView() {
    _viewMode = OrbitViewMode.innerCircle;
    if (_searchActive) {
      _onSearchClose();
    }
    // 198: also reset the Inner-Circle surface's transient state (arcs collapse,
    // labels off, edit exits, find clears). Knobs persist.
    _innerCircleResetTick.value++;
  }

  // Replays one targeted refresh per buffered reason on Feed -> Orbit
  // re-activation — NOT a lone friends-only `_loadOrbitData` (the six handlers
  // are heterogeneous).
  void _replayDirtyOrbitWork() {
    if (_dirtyFriendPeerIds.isNotEmpty) {
      final peerIds = _dirtyFriendPeerIds.toList();
      _dirtyFriendPeerIds.clear();
      for (final peerId in peerIds) {
        _enqueueOrbitFriendRefresh(peerId);
      }
    }
    if (_dirtyGroupIds.isNotEmpty) {
      final groupIds = _dirtyGroupIds.toList();
      _dirtyGroupIds.clear();
      for (final groupId in groupIds) {
        _enqueueOrbitGroupRefresh(groupId);
      }
    }
    if (_introsDirty) {
      _introsDirty = false;
      _loadIntroductions();
    }
    if (_invitesDirty) {
      _invitesDirty = false;
      unawaited(_loadPendingGroupInvites());
    }
  }

  Future<void> _loadQualityPreference() async {
    final pref = await loadImageQualityPreference(
      secureKeyStore: widget.secureKeyStore,
    );
    _qualityPreference = pref;
  }

  Future<void> _loadVideoQualityPreference() async {
    final pref = await loadVideoQualityPreference(
      secureKeyStore: widget.secureKeyStore,
    );
    _videoQualityPreference = pref;
  }

  // 206 — the center self-avatar opens the FULL Settings screen (functionally
  // equivalent to the removed Feed-header entry): the SAME shared
  // AppShellController + posts-privacy repo + the orbit-threaded nearby service.
  // A tap-only detector fires onTap twice on a double-tap and once on a
  // long-press release, so a single-flight latch (released on any pop path via
  // whenComplete) guards against stacked Settings routes.
  void _onSelfAvatarTap() {
    final shell = widget.appShellController;
    final privacy = widget.postsPrivacySettingsRepository;
    if (shell == null || privacy == null || _settingsRouteActive) return;
    _settingsRouteActive = true;
    Navigator.of(context)
        .push(
          buildSettingsSlideUpRoute<void>(
            builder: (_) => SettingsWired(
              identityRepo: widget.identityRepo,
              bridge: widget.bridge,
              contactRepo: widget.contactRepo,
              p2pService: widget.p2pService,
              secureKeyStore: widget.secureKeyStore,
              imageProcessor: widget.imageProcessor,
              appShellController: shell,
              postsPrivacySettingsRepository: privacy,
              introductionRepository: widget.introductionRepository,
              nearbyLocationService: widget.nearbyLocationService,
              transportMetrics: widget.transportMetrics,
              accountMigrationRunTransfer: widget.accountMigrationRunTransfer,
              accountMigrationSizeGate: widget.accountMigrationSizeGate,
              // 209 — the Settings QR tiles run the SAME handlers the retired
              // orbit chrome fed (bodies unchanged → INV-196-7 verbatim); the
              // returned pop-futures drive Settings' single-flight latch.
              onMyQrRequested: _onMyQR,
              onScanQrRequested: _onScanQR,
              // 229: storage management for the Media & storage sheet —
              // injected by hosts/tests, else built over this orbit's own
              // repositories.
              mediaStorageManager: widget.mediaStorageManager ??
                  MediaStorageManager(
                    repository: widget.mediaAttachmentRepo,
                    documentsDirectoryProvider: () async =>
                        (await getApplicationDocumentsDirectory()).path,
                  ),
              mediaStorageScopesProvider: widget.mediaStorageScopesProvider ??
                  _loadMediaStorageScopes,
            ),
          ),
        )
        .whenComplete(() {
      _settingsRouteActive = false;
    });
  }

  /// 229: the scopes the Media & storage sheet can measure/clear — one per
  /// active contact (direct lane) and one per group (discussions AND
  /// announcements share the group lane).
  Future<List<MediaStorageScopeOption>> _loadMediaStorageScopes() async {
    final options = <MediaStorageScopeOption>[];
    try {
      final contacts = await widget.contactRepo.getActiveContacts();
      options.addAll(
        contacts.map(
          (contact) => MediaStorageScopeOption(
            scope: MediaLibraryScope.direct(contact.peerId),
            label: contact.username,
          ),
        ),
      );
    } catch (_) {}
    try {
      final groups = await widget.groupRepository?.getActiveGroups();
      if (groups != null) {
        options.addAll(
          groups.map(
            (group) => MediaStorageScopeOption(
              scope: MediaLibraryScope.group(group.id),
              label: group.name,
            ),
          ),
        );
      }
    } catch (_) {}
    return options;
  }

  void _loadIdentity() async {
    try {
      final identity = await widget.identityRepo.loadIdentity();
      if (identity == null || !mounted) return;

      final avatarBytes = await IdentityAvatarResolver.resolve(identity);

      if (!mounted) return;

      _identity = identity;
      _avatarBytes = avatarBytes;
      _publishAllProjections();
      // Now that identity is loaded, load introductions
      _loadIntroductions();
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ORBIT_FL_LOAD_IDENTITY_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _loadOrbitData() async {
    try {
      final active = await loadOrbitData(
        contactRepo: widget.contactRepo,
        messageRepo: widget.messageRepo,
        mediaAttachmentRepo: widget.mediaAttachmentRepo,
      );
      if (!mounted) return;

      _activeFriends = active;
      _activeFriendsLoaded = true;
      _blockedPeerIds = _collectBlockedPeerIds(
        activeFriends: _activeFriends,
        archivedFriends: _archivedFriends,
      );
      _publishAllProjections();
    } catch (e) {
      if (mounted) {
        _activeFriendsLoaded = true;
        _publishAllProjections();
      }
      emitFlowEvent(
        layer: 'FL',
        event: 'ORBIT_FL_LOAD_DATA_ERROR',
        details: {'error': e.toString(), 'segment': 'active'},
      );
    }

    try {
      final archived = await loadOrbitData(
        contactRepo: widget.contactRepo,
        messageRepo: widget.messageRepo,
        mediaAttachmentRepo: widget.mediaAttachmentRepo,
        includeArchived: true,
      );
      if (!mounted) return;

      _archivedFriends = archived;
      _archivedFriendsLoaded = true;
      _blockedPeerIds = _collectBlockedPeerIds(
        activeFriends: _activeFriends,
        archivedFriends: _archivedFriends,
      );
      _publishAllProjections();
    } catch (e) {
      if (mounted) {
        _archivedFriendsLoaded = true;
        _publishAllProjections();
      }
      emitFlowEvent(
        layer: 'FL',
        event: 'ORBIT_FL_LOAD_DATA_ERROR',
        details: {'error': e.toString(), 'segment': 'archived'},
      );
    }
  }

  Future<void> _loadGroupData() async {
    final groupRepository = widget.groupRepository;
    final groupMessageRepository = widget.groupMessageRepository;
    if (groupRepository == null || groupMessageRepository == null) {
      _activeGroupsLoaded = true;
      _archivedGroupsLoaded = true;
      _publishAllProjections();
      return;
    }

    try {
      final active = await loadOrbitGroups(
        groupRepo: groupRepository,
        msgRepo: groupMessageRepository,
        mediaAttachmentRepo: widget.mediaAttachmentRepo,
      );
      // E: tag half-materialized groups (topic-join not yet succeeded) with
      // their bounded rejoin attempt count so the row can badge "Joining…" /
      // "Couldn't join".
      final rejoinStates = await groupRepository.loadGroupRejoinStates();
      if (!mounted) return;

      _activeGroups = active
          .map(
            (group) => group.copyWith(
              rejoinAttemptCount: rejoinStates[group.groupId]?.attemptCount,
            ),
          )
          .toList();
      _activeGroupsLoaded = true;
      // 203 B2: group-funnel publishes go through publish-all — the rings'
      // ONLY feed is the header projection's innerItems, so a list-only
      // publish here left a freshly loaded group off the Inner-Circle rings
      // until an unrelated friend/identity refresh happened to flush it.
      _publishAllProjections();
    } catch (e) {
      if (mounted) {
        _activeGroupsLoaded = true;
        _publishAllProjections();
      }
      emitFlowEvent(
        layer: 'FL',
        event: 'ORBIT_FL_LOAD_GROUP_DATA_ERROR',
        details: {'error': e.toString(), 'segment': 'active'},
      );
    }

    try {
      final archived = await loadOrbitGroups(
        groupRepo: groupRepository,
        msgRepo: groupMessageRepository,
        mediaAttachmentRepo: widget.mediaAttachmentRepo,
        includeArchived: true,
      );
      if (!mounted) return;
      _archivedGroups = archived;
      _archivedGroupsLoaded = true;
      _publishAllProjections();
    } catch (e) {
      if (mounted) {
        _archivedGroupsLoaded = true;
        _publishAllProjections();
      }
      emitFlowEvent(
        layer: 'FL',
        event: 'ORBIT_FL_LOAD_GROUP_DATA_ERROR',
        details: {'error': e.toString(), 'segment': 'archived'},
      );
    }
  }

  Future<void> _loadPendingGroupInvites() async {
    final inviteListener = widget.groupInviteListener;
    if (inviteListener == null) {
      if (_pendingGroupInvites.isNotEmpty) {
        _pendingGroupInvites = const [];
        _publishListProjection();
      }
      return;
    }

    try {
      final invites = await inviteListener.pendingInviteRepo
          .getPendingInvites();
      if (!mounted) return;
      // B2: drop invites whose group is already joined (materialized orphan).
      // Tolerates _activeGroups not yet loaded (empty set → no filtering).
      // Membership-only filter; expired-but-unjoined invites keep their card.
      final joinedGroupIds = _activeGroups
          .map((group) => group.groupId)
          .toSet();
      _pendingGroupInvites = invites
          .where(
            (invite) =>
                !joinedGroupIds.contains(invite.groupId) &&
                // 153: keep optimistically-declined rows hidden across every
                // reactive reload until their deferred commit/undo resolves.
                !_optimisticallyDeclinedInviteIds.contains(invite.groupId),
          )
          .toList();
      _publishListProjection();
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ORBIT_FL_LOAD_PENDING_GROUP_INVITES_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _loadIntroReviewSeenKeys() async {
    final repository = widget.introReviewSeenRepository;
    if (repository == null) return;

    try {
      final seenKeys = await repository.loadSeenKeys();
      if (!mounted) return;
      _seenReviewKeys = seenKeys;
      _publishListProjection();
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ORBIT_FL_LOAD_INTRO_REVIEW_SEEN_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Set<String> _collectBlockedPeerIds({
    required List<OrbitFriend> activeFriends,
    required List<OrbitFriend> archivedFriends,
  }) {
    final blocked = <String>{};
    for (final friend in activeFriends) {
      if (friend.isBlocked) blocked.add(friend.peerId);
    }
    for (final friend in archivedFriends) {
      if (friend.isBlocked) blocked.add(friend.peerId);
    }
    return blocked;
  }

  // 202: enqueue a burst-driven friend/group refresh into the trailing-flush
  // coalescer. Discrete user actions (contact CRUD, group lifecycle, route
  // results) stay DIRECT — only the high-frequency message streams + the dirty
  // replay funnel through here so a same-key burst costs one snapshot load.
  void _enqueueOrbitFriendRefresh(String peerId) {
    _pendingFriendRefreshPeerIds.add(peerId);
    _orbitRefreshCoalesceTimer ??=
        Timer(_orbitRefreshCoalesceWindow, _flushOrbitRefreshes);
  }

  void _enqueueOrbitGroupRefresh(String groupId) {
    _pendingGroupRefreshGroupIds.add(groupId);
    _orbitRefreshCoalesceTimer ??=
        Timer(_orbitRefreshCoalesceWindow, _flushOrbitRefreshes);
  }

  void _flushOrbitRefreshes() {
    _orbitRefreshCoalesceTimer = null;
    if (_pendingFriendRefreshPeerIds.isNotEmpty) {
      final peerIds = _pendingFriendRefreshPeerIds.toList();
      _pendingFriendRefreshPeerIds.clear();
      for (final peerId in peerIds) {
        unawaited(_refreshOrbitFriend(peerId));
      }
    }
    if (_pendingGroupRefreshGroupIds.isNotEmpty) {
      final groupIds = _pendingGroupRefreshGroupIds.toList();
      _pendingGroupRefreshGroupIds.clear();
      for (final groupId in groupIds) {
        unawaited(_refreshOrbitGroup(groupId));
      }
    }
  }

  Future<void> _refreshOrbitFriend(String peerId) async {
    try {
      final friend = await loadOrbitFriendSnapshot(
        contactRepo: widget.contactRepo,
        messageRepo: widget.messageRepo,
        contactPeerId: peerId,
        mediaAttachmentRepo: widget.mediaAttachmentRepo,
      );
      if (!mounted) return;

      final activeFriends = List<OrbitFriend>.from(_activeFriends)
        ..removeWhere((entry) => entry.peerId == peerId);
      final archivedFriends = List<OrbitFriend>.from(_archivedFriends)
        ..removeWhere((entry) => entry.peerId == peerId);
      final blockedPeerIds = Set<String>.from(_blockedPeerIds)..remove(peerId);

      if (friend != null) {
        if (friend.isArchived) {
          archivedFriends.add(friend);
        } else {
          activeFriends.add(friend);
        }
        if (friend.isBlocked) {
          blockedPeerIds.add(peerId);
        }
      }

      _sortFriends(activeFriends);
      _sortFriends(archivedFriends);
      _activeFriends = activeFriends;
      _archivedFriends = archivedFriends;
      _blockedPeerIds = blockedPeerIds;
      _publishAllProjections();
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ORBIT_FL_FRIEND_REFRESH_ERROR',
        details: {'peerId': peerId, 'error': e.toString()},
      );
      await _loadOrbitData();
    }
  }

  Future<void> _refreshOrbitGroup(String groupId) async {
    final groupRepository = widget.groupRepository;
    final groupMessageRepository = widget.groupMessageRepository;
    if (groupRepository == null || groupMessageRepository == null) return;

    try {
      final group = await loadOrbitGroupSnapshot(
        groupRepo: groupRepository,
        msgRepo: groupMessageRepository,
        groupId: groupId,
        mediaAttachmentRepo: widget.mediaAttachmentRepo,
      );
      // Re-derive the bounded rejoin attempt count (the snapshot loader leaves
      // it null) so a single-group refresh keeps the "Joining…" / "Couldn't
      // join" badge and its G2 Retry/Leave affordances, mirroring the full
      // loader — otherwise tapping "Retry now" (which refreshes this row) would
      // make the still-stuck group's badge + actions silently vanish.
      final rejoinStates = await groupRepository.loadGroupRejoinStates();
      if (!mounted) return;

      final refreshed = group?.copyWith(
        rejoinAttemptCount: rejoinStates[groupId]?.attemptCount,
      );

      final activeGroups = List<OrbitGroup>.from(_activeGroups)
        ..removeWhere((entry) => entry.groupId == groupId);
      final archivedGroups = List<OrbitGroup>.from(_archivedGroups)
        ..removeWhere((entry) => entry.groupId == groupId);

      if (refreshed != null) {
        if (refreshed.group.isArchived) {
          archivedGroups.add(refreshed);
        } else {
          activeGroups.add(refreshed);
        }
      }

      _sortGroups(activeGroups);
      _sortGroups(archivedGroups);
      _activeGroups = activeGroups;
      _archivedGroups = archivedGroups;
      // 203 B2: publish-all so seat/remove/unread/metadata changes reach the
      // ring projection live (see _loadGroupData).
      _publishAllProjections();
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ORBIT_FL_GROUP_REFRESH_ERROR',
        details: {'groupId': groupId, 'error': e.toString()},
      );
      await _loadGroupData();
    }
  }

  void _sortFriends(List<OrbitFriend> friends) {
    friends.sort((a, b) {
      final aTime = a.lastMessageTimestamp ?? '';
      final bTime = b.lastMessageTimestamp ?? '';
      return bTime.compareTo(aTime);
    });
  }

  void _sortGroups(List<OrbitGroup> groups) {
    groups.sort((a, b) {
      final aTime = a.lastActivityTimestamp?.toUtc().toIso8601String() ?? '';
      final bTime = b.lastActivityTimestamp?.toUtc().toIso8601String() ?? '';
      return bTime.compareTo(aTime);
    });
  }

  Future<void> _loadIntroductions() async {
    final introRepo = widget.introductionRepository;
    if (introRepo == null || _identity == null) return;
    final requestId = ++_introLoadRequestId;

    try {
      final ownPeerId = _identity!.peerId;
      await expireOldIntroductions(
        introRepo: introRepo,
        peerId: ownPeerId,
        contactRepo: widget.contactRepo,
        messageRepo: widget.messageRepo,
        bridge: widget.bridge,
      );
      final pending = await loadIntroductionsForUser(
        introRepo: introRepo,
        peerId: ownPeerId,
      );
      final grouped = groupByIntroducer(pending);
      final foldedReviewItems = foldIntroductionsForReview(
        introductions: pending,
        ownPeerId: ownPeerId,
      );
      final usernames = <String, String>{};
      for (final intro in pending) {
        usernames.putIfAbsent(
          intro.introducerId,
          () => intro.introducerUsername ?? 'Unknown',
        );
      }
      if (!mounted || requestId != _introLoadRequestId) return;
      _introsCount = countFoldedPendingIntroductionTargets(
        introductions: pending,
        ownPeerId: ownPeerId,
      );
      _groupedIntros = grouped;
      _foldedReviewItems = foldedReviewItems;
      _introducerUsernames = usernames;
      _publishListProjection();
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ORBIT_FL_LOAD_INTROS_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  FoldedIntroductionReviewItem? _foldedIntroForActionId(String introductionId) {
    for (final item in _foldedReviewItems) {
      if (item.displaySourceIntroductionId == introductionId ||
          item.introductionIds.contains(introductionId)) {
        return item;
      }
    }
    return null;
  }

  bool _isAnyFoldedIntroIdProcessing(FoldedIntroductionReviewItem item) {
    return item.introductionIds.any(_processingIntroductionIds.contains);
  }

  String _otherPeerIdForIntroduction(
    IntroductionModel introduction,
    String ownPeerId,
  ) {
    if (introduction.recipientId == ownPeerId) {
      return introduction.introducedId;
    }
    if (introduction.introducedId == ownPeerId) {
      return introduction.recipientId;
    }
    return '';
  }

  void _markContactChanged(String peerId) {
    _changedContactPeerIds.add(peerId);
  }

  void _markGroupChanged(String groupId) {
    _changedGroupIds.add(groupId);
  }

  FeedRouteChanges? _buildRouteChanges() {
    final changes = FeedRouteChanges(
      changedContactPeerIds: Set<String>.from(_changedContactPeerIds),
      changedGroupIds: Set<String>.from(_changedGroupIds),
      refreshPendingIntroductions: _refreshPendingIntroductionsOnPop,
    );
    return changes.hasChanges ? changes : null;
  }

  void _startListeningForIntroductions() {
    final listener = widget.introductionListener;
    if (listener == null) return;

    _introReceivedSubscription = listener.introReceivedStream.listen(
      (_) {
        if (!_isOrbitActive) {
          _introsDirty = true;
          return;
        }
        _loadIntroductions();
      },
      onError: (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'ORBIT_INTRO_RECEIVED_STREAM_ERROR',
          details: {'error': error.toString()},
        );
      },
    );

    _introStatusSubscription = listener.introStatusChangedStream.listen(
      (intro) {
        if (!_isOrbitActive) {
          _introsDirty = true;
          final identity = _identity;
          if (identity != null &&
              intro.status == IntroductionOverallStatus.mutualAccepted) {
            final otherPeerId = intro.recipientId == identity.peerId
                ? intro.introducedId
                : intro.recipientId;
            if (otherPeerId.isNotEmpty) {
              _dirtyFriendPeerIds.add(otherPeerId);
            }
          }
          return;
        }
        _loadIntroductions();
        final identity = _identity;
        if (identity == null ||
            intro.status != IntroductionOverallStatus.mutualAccepted) {
          return;
        }
        final otherPeerId = intro.recipientId == identity.peerId
            ? intro.introducedId
            : intro.recipientId;
        if (otherPeerId.isNotEmpty) {
          unawaited(_refreshOrbitFriend(otherPeerId));
        }
      },
      onError: (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'ORBIT_INTRO_STATUS_STREAM_ERROR',
          details: {'error': error.toString()},
        );
      },
    );
  }

  void _startListeningForPendingGroupInvites() {
    final listener = widget.groupInviteListener;
    if (listener == null) return;

    _groupJoinedInviteSubscription = listener.groupJoinedStream.listen(
      (group) {
        _markGroupChanged(group.id);
        if (!_isOrbitActive) {
          _dirtyGroupIds.add(group.id);
          _invitesDirty = true;
          return;
        }
        unawaited(_refreshOrbitGroup(group.id));
        unawaited(_loadPendingGroupInvites());
      },
      onError: (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'ORBIT_GROUP_JOINED_STREAM_ERROR',
          details: {'error': error.toString()},
        );
      },
    );

    _pendingGroupInviteSubscription = listener.pendingInviteStream.listen(
      (_) {
        if (!_isOrbitActive) {
          _invitesDirty = true;
          return;
        }
        unawaited(_loadPendingGroupInvites());
      },
      onError: (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'ORBIT_PENDING_GROUP_INVITE_STREAM_ERROR',
          details: {'error': error.toString()},
        );
      },
    );
  }

  Future<void> _onAcceptIntro(String introductionId) async {
    final identity = _identity;
    final introRepo = widget.introductionRepository;
    if (identity == null || introRepo == null) {
      return;
    }

    final foldedIntro = _foldedIntroForActionId(introductionId);
    if (foldedIntro != null) {
      if (_isAnyFoldedIntroIdProcessing(foldedIntro)) {
        return;
      }

      final processingIds = Set<String>.from(foldedIntro.introductionIds);
      _processingIntroductionIds.addAll(processingIds);
      _publishListProjection();
      try {
        final batch = await acceptFoldedIntroduction(
          introRepo: introRepo,
          contactRepo: widget.contactRepo,
          p2pService: widget.p2pService,
          bridge: widget.bridge,
          foldedIntroduction: foldedIntro,
          ownPeerId: identity.peerId,
          ownUsername: identity.username,
          messageRepo: widget.messageRepo,
        );
        final changedPeerIds = <String>{};
        for (final result in batch.appliedResults) {
          final updated = result.introduction;
          if (updated == null ||
              updated.status != IntroductionOverallStatus.mutualAccepted) {
            continue;
          }
          final otherPeerId = _otherPeerIdForIntroduction(
            updated,
            identity.peerId,
          );
          if (otherPeerId.isNotEmpty) {
            changedPeerIds.add(otherPeerId);
          }
        }
        for (final peerId in changedPeerIds) {
          _markContactChanged(peerId);
          await _refreshOrbitFriend(peerId);
        }
        _refreshPendingIntroductionsOnPop = true;
        await _loadIntroductions();
      } finally {
        _processingIntroductionIds.removeAll(processingIds);
        if (mounted) {
          _publishListProjection();
        }
      }
      return;
    }

    if (_processingIntroductionIds.contains(introductionId)) {
      return;
    }

    _processingIntroductionIds.add(introductionId);
    _publishListProjection();
    try {
      final updated = await acceptIntroduction(
        introRepo: introRepo,
        contactRepo: widget.contactRepo,
        p2pService: widget.p2pService,
        bridge: widget.bridge,
        introductionId: introductionId,
        ownPeerId: identity.peerId,
        ownUsername: identity.username,
        messageRepo: widget.messageRepo,
      );
      if (updated != null &&
          updated.status == IntroductionOverallStatus.mutualAccepted) {
        final otherPeerId = updated.recipientId == identity.peerId
            ? updated.introducedId
            : updated.recipientId;
        if (otherPeerId.isNotEmpty) {
          _markContactChanged(otherPeerId);
          await _refreshOrbitFriend(otherPeerId);
        }
      }
      _refreshPendingIntroductionsOnPop = true;
      await _loadIntroductions();
    } finally {
      _processingIntroductionIds.remove(introductionId);
      if (mounted) {
        _publishListProjection();
      }
    }
  }

  Future<void> _onPassIntro(String introductionId) async {
    final identity = _identity;
    final introRepo = widget.introductionRepository;
    if (identity == null || introRepo == null) {
      return;
    }

    final foldedIntro = _foldedIntroForActionId(introductionId);
    if (foldedIntro != null) {
      if (_isAnyFoldedIntroIdProcessing(foldedIntro)) {
        return;
      }

      final processingIds = Set<String>.from(foldedIntro.introductionIds);
      _processingIntroductionIds.addAll(processingIds);
      _publishListProjection();
      try {
        await passFoldedIntroduction(
          introRepo: introRepo,
          contactRepo: widget.contactRepo,
          p2pService: widget.p2pService,
          bridge: widget.bridge,
          foldedIntroduction: foldedIntro,
          ownPeerId: identity.peerId,
          ownUsername: identity.username,
        );
        _refreshPendingIntroductionsOnPop = true;
        await _loadIntroductions();
      } finally {
        _processingIntroductionIds.removeAll(processingIds);
        if (mounted) {
          _publishListProjection();
        }
      }
      return;
    }

    if (_processingIntroductionIds.contains(introductionId)) {
      return;
    }

    _processingIntroductionIds.add(introductionId);
    _publishListProjection();
    try {
      await passIntroduction(
        introRepo: introRepo,
        contactRepo: widget.contactRepo,
        p2pService: widget.p2pService,
        bridge: widget.bridge,
        introductionId: introductionId,
        ownPeerId: identity.peerId,
        ownUsername: identity.username,
      );
      _refreshPendingIntroductionsOnPop = true;
      await _loadIntroductions();
    } finally {
      _processingIntroductionIds.remove(introductionId);
      if (mounted) {
        _publishListProjection();
      }
    }
  }

  Future<void> _onDeleteIntro(String introductionId) async {
    final introRepo = widget.introductionRepository;
    if (_identity == null || introRepo == null) return;

    final confirmed = await showConfirmationDialog(
      context: context,
      title: 'Delete introduction?',
      description:
          'This removes the introduction from your Orbit list. This cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (!confirmed || !mounted) return;

    try {
      await introRepo.deleteIntroduction(introductionId);
      _openRowNotifier.value = null;
      _refreshPendingIntroductionsOnPop = true;
      await _loadIntroductions();
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ORBIT_FL_DELETE_INTRO_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _onAcceptPendingInvite(PendingGroupInvite invite) async {
    final inviteListener = widget.groupInviteListener;
    final groupRepository = widget.groupRepository;
    final groupMessageRepository = widget.groupMessageRepository;
    final groupMessageListener = widget.groupMessageListener;
    if (inviteListener == null ||
        groupRepository == null ||
        groupMessageRepository == null ||
        groupMessageListener == null ||
        _processingPendingInviteIds.contains(invite.groupId)) {
      return;
    }

    setState(() => _processingPendingInviteIds.add(invite.groupId));
    try {
      await _drainPendingGroupInviteInboxBeforeAccept(
        inviteListener,
        invite.groupId,
      );
      final identity = await widget.identityRepo.loadIdentity();
      final localTransportPeerId = widget.p2pService.currentState.peerId;
      final (result, group) = await _acceptPendingInviteWithRecoveryRetry(
        inviteListener: inviteListener,
        invite: invite,
        groupRepository: groupRepository,
        groupMessageRepository: groupMessageRepository,
        groupMessageListener: groupMessageListener,
        senderPeerId: identity?.peerId,
        senderPublicKey: identity?.publicKey,
        senderPrivateKey: identity?.privateKey,
        senderUsername: identity?.username,
        localTransportPeerId: localTransportPeerId,
        ownMlKemPublicKey: identity?.mlKemPublicKey,
      );
      if (group != null) {
        _markGroupChanged(group.id);
      }
      _refreshPendingIntroductionsOnPop = true;
      await _loadPendingGroupInvites();
      if (group != null) {
        await _refreshOrbitGroup(group.id);
      }
      if (!mounted) return;

      final l10n = AppLocalizations.of(context)!;
      switch (result) {
        case AcceptPendingGroupInviteResult.success:
          // 208: navigating accept — open the group chat with NO confirmation
          // snackbar.
          if (group != null && mounted) {
            _openGroupConversationFromModel(group);
          }
          break;
        case AcceptPendingGroupInviteResult.notFound:
          _showSnackBar('Invite no longer available');
          break;
        case AcceptPendingGroupInviteResult.expired:
          _showSnackBar('Invite expired');
          break;
        case AcceptPendingGroupInviteResult.expiredFreshness:
          _showSnackBar(l10n.group_invite_expired_ask_resend);
          break;
        case AcceptPendingGroupInviteResult.revoked:
          _showSnackBar('Invite was revoked');
          break;
        case AcceptPendingGroupInviteResult.alreadyUsed:
          _showSnackBar('Invite already used');
          break;
        case AcceptPendingGroupInviteResult.wrongIdentity:
          _showSnackBar('Invite is for another identity');
          break;
        case AcceptPendingGroupInviteResult.repairPending:
          _showSnackBar('Invite needs fresh key material');
          break;
        case AcceptPendingGroupInviteResult.invalidPayload:
          _showSnackBar('Invite is no longer valid');
          break;
        case AcceptPendingGroupInviteResult.duplicateGroup:
          _showSnackBar('Group already added');
          break;
        case AcceptPendingGroupInviteResult.bridgeError:
          _showSnackBar('Failed to accept invite');
          break;
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ORBIT_FL_ACCEPT_PENDING_GROUP_INVITE_ERROR',
        details: {
          'groupId': invite.groupId.length > 8
              ? invite.groupId.substring(0, 8)
              : invite.groupId,
          'error': e.toString(),
        },
      );
      await _loadPendingGroupInvites();
      if (mounted) {
        _showSnackBar('Failed to accept invite');
      }
    } finally {
      if (mounted) {
        setState(() => _processingPendingInviteIds.remove(invite.groupId));
      }
    }
  }

  Future<(AcceptPendingGroupInviteResult, GroupModel?)>
  _acceptPendingInviteWithRecoveryRetry({
    required GroupInviteListener inviteListener,
    required PendingGroupInvite invite,
    required GroupRepository groupRepository,
    required GroupMessageRepository groupMessageRepository,
    required GroupMessageListener groupMessageListener,
    required String? senderPeerId,
    required String? senderPublicKey,
    required String? senderPrivateKey,
    required String? senderUsername,
    required String? localTransportPeerId,
    required String? ownMlKemPublicKey,
  }) async {
    Future<(AcceptPendingGroupInviteResult, GroupModel?)> attempt() {
      return acceptPendingGroupInvite(
        pendingInviteRepo: inviteListener.pendingInviteRepo,
        groupRepo: groupRepository,
        contactRepo: widget.contactRepo,
        msgRepo: groupMessageRepository,
        bridge: widget.bridge,
        groupId: invite.groupId,
        mediaAttachmentRepo: widget.mediaAttachmentRepo,
        reactionRepo: widget.reactionRepository,
        groupMessageListener: groupMessageListener,
        senderPeerId: senderPeerId,
        senderPublicKey: senderPublicKey,
        senderPrivateKey: senderPrivateKey,
        senderUsername: senderUsername,
        ownDeviceId: localTransportPeerId,
        ownTransportPeerId: localTransportPeerId,
        ownMlKemPublicKey: ownMlKemPublicKey,
        ownKeyPackageId: defaultGroupWelcomeKeyPackageIdForDevice(
          localTransportPeerId,
        ),
        ownKeyPackagePublicMaterial: ownMlKemPublicKey,
        onJoinConfigRequest: kOnJoinMetadataResyncEnabled
            ? ({required group, required invite}) async {
                final inviterMember = await groupRepository.getMember(
                  group.id,
                  invite.senderPeerId,
                );
                unawaited(
                  sendOnJoinGroupConfigRequest(
                    p2pService: widget.p2pService,
                    bridge: widget.bridge,
                    groupId: group.id,
                    requesterPeerId: senderPeerId ?? '',
                    inviterPeerId: invite.senderPeerId,
                    inviterMlKemPublicKey: inviterMember?.mlKemPublicKey,
                  ),
                );
              }
            : null,
        drainAcceptedInboxAllPages: true,
        acceptedInboxDrainMaxAttempts: 4,
      );
    }

    var outcome = await attempt();
    for (
      var retry = 0;
      outcome.$1 == AcceptPendingGroupInviteResult.bridgeError &&
          outcome.$2 == null &&
          retry < _acceptRecoveryRetryCount;
      retry++
    ) {
      if (await inviteListener.pendingInviteRepo.getPendingInvite(
            invite.groupId,
          ) ==
          null) {
        return outcome;
      }
      await Future<void>.delayed(_acceptRecoveryRetryDelay);
      await _drainPendingGroupInviteInboxBeforeAccept(
        inviteListener,
        invite.groupId,
      );
      outcome = await attempt();
    }
    return outcome;
  }

  Future<void> _drainPendingGroupInviteInboxBeforeAccept(
    GroupInviteListener inviteListener,
    String groupId,
  ) async {
    try {
      final p2pService = widget.p2pService;
      if (p2pService is P2PFullInboxDrain) {
        await (p2pService as P2PFullInboxDrain).drainOfflineInboxFully();
      } else {
        await p2pService.drainOfflineInbox();
      }
      await inviteListener.waitForIdle();
      await widget.waitForGroupMembershipUpdateIdle?.call();
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ORBIT_FL_ACCEPT_PENDING_GROUP_INVITE_PREFLIGHT_WARNING',
        details: {
          'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
          'error': e.toString(),
        },
      );
    }
  }

  /// 153: optimistically hide the row and offer a localized Undo (parity with
  /// group_list). The real decline — and its irreversible decline-ack — is
  /// deferred behind [kDeclineUndoWindow] and commits exactly once on timeout
  /// (not at all on Undo / dispose). Runs synchronously so the hide is instant;
  /// the held `_processingPendingInviteIds` guard makes the commit once-only
  /// under double-tap.
  void _onDeclinePendingInvite(PendingGroupInvite invite) {
    final inviteListener = widget.groupInviteListener;
    if (inviteListener == null ||
        _processingPendingInviteIds.contains(invite.groupId)) {
      return;
    }

    _processingPendingInviteIds.add(invite.groupId);
    _optimisticallyDeclinedInviteIds.add(invite.groupId);
    _pendingGroupInvites = _pendingGroupInvites
        .where((i) => !_optimisticallyDeclinedInviteIds.contains(i.groupId))
        .toList();
    _refreshPendingIntroductionsOnPop = true;
    _publishListProjection();

    final l10n = AppLocalizations.of(context)!;
    _declineScaffoldMessenger = ScaffoldMessenger.of(context);
    _showSnackBar(
      l10n.group_invite_declined,
      duration: kDeclineUndoWindow + const Duration(seconds: 1),
      action: SnackBarAction(
        label: l10n.feed_undo,
        onPressed: () => _undoDecline(invite),
      ),
    );

    _declineCommitTimers[invite.groupId] = Timer(
      kDeclineUndoWindow,
      () => unawaited(_commitDecline(invite)),
    );
  }

  /// Cancel a pending decline before its window elapses: re-surface the invite,
  /// emit UNDONE, never send the decline-ack. No-op if the commit already fired
  /// (late-tap race — the Timer is already gone).
  void _undoDecline(PendingGroupInvite invite) {
    // The SnackBar (and its Undo action) can outlive this State on the
    // app-level messenger; a stale tap after dispose must be a safe no-op.
    if (!mounted) return;
    final timer = _declineCommitTimers.remove(invite.groupId);
    if (timer == null) return;
    timer.cancel();
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_DECLINE_UNDONE',
      details: {
        'surface': 'orbit',
        'groupId': invite.groupId.length > 8
            ? invite.groupId.substring(0, 8)
            : invite.groupId,
      },
    );
    _optimisticallyDeclinedInviteIds.remove(invite.groupId);
    _processingPendingInviteIds.remove(invite.groupId);
    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
    }
    unawaited(_loadPendingGroupInvites());
  }

  /// Fire the deferred decline once the undo window elapses. Runs the real
  /// (already-idempotent) use-case, then in `finally` releases the optimistic
  /// hide + processing guard and reloads — so a throwing commit re-surfaces the
  /// still-present invite, while a successful commit keeps it gone.
  Future<void> _commitDecline(PendingGroupInvite invite) async {
    // Already undone/cancelled (or this is a duplicate fire) — commit once.
    if (_declineCommitTimers.remove(invite.groupId) == null) return;
    // 153 (review P2): the undo window has closed — drop the Undo affordance the
    // moment the commit fires, not after the (possibly slow) use-case + reload.
    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_DECLINE_COMMITTED',
      details: {
        'surface': 'orbit',
        'groupId': invite.groupId.length > 8
            ? invite.groupId.substring(0, 8)
            : invite.groupId,
      },
    );

    final inviteListener = widget.groupInviteListener;
    DeclinePendingGroupInviteResult? result;
    Object? error;
    try {
      if (inviteListener != null) {
        // Best-effort decline-ack deps (the local decline never blocks on them).
        final identity = await widget.identityRepo.loadIdentity();
        result = await declinePendingGroupInvite(
          pendingInviteRepo: inviteListener.pendingInviteRepo,
          groupId: invite.groupId,
          p2pService: widget.p2pService,
          bridge: widget.bridge,
          contactRepo: widget.contactRepo,
          declinerPeerId: identity?.peerId,
          declinerPrivateKey: identity?.privateKey,
        );
      }
    } catch (e) {
      error = e;
      emitFlowEvent(
        layer: 'FL',
        event: 'ORBIT_FL_DECLINE_PENDING_GROUP_INVITE_ERROR',
        details: {
          'groupId': invite.groupId.length > 8
              ? invite.groupId.substring(0, 8)
              : invite.groupId,
          'error': e.toString(),
        },
      );
    } finally {
      _optimisticallyDeclinedInviteIds.remove(invite.groupId);
      _processingPendingInviteIds.remove(invite.groupId);
      await _loadPendingGroupInvites();
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        final l10n = AppLocalizations.of(context)!;
        if (error != null) {
          _showSnackBar(l10n.group_invite_decline_failed);
        } else if (result != null) {
          switch (result) {
            case DeclinePendingGroupInviteResult.success:
              _showSnackBar(l10n.group_invite_declined);
              break;
            case DeclinePendingGroupInviteResult.notFound:
              _showSnackBar(l10n.group_invite_no_longer_available);
              break;
            case DeclinePendingGroupInviteResult.expired:
              _showSnackBar(l10n.group_invite_expired);
              break;
          }
        }
      }
    }
  }

  void _showSnackBar(
    String message, {
    Duration? duration,
    SnackBarAction? action,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: duration ?? const Duration(seconds: 4),
        action: action,
      ),
    );
  }

  void _onIntroSendMessage(String peerId) {
    // Find the contact matching this peerId and navigate to conversation
    final friend = _activeFriends.cast<OrbitFriend?>().firstWhere(
      (f) => f!.peerId == peerId,
      orElse: () => null,
    );
    if (friend != null) {
      _onFriendTap(friend);
    }
  }

  void _startListeningForGroupMessages() {
    final listener = widget.groupMessageListener;
    if (listener == null) return;

    _groupMessageSubscription = listener.groupMessageStream.listen(
      (message) {
        _markGroupChanged(message.groupId);
        if (!_isOrbitActive) {
          _dirtyGroupIds.add(message.groupId);
          return;
        }
        _enqueueOrbitGroupRefresh(message.groupId);
      },
      onError: (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'ORBIT_GROUP_MSG_STREAM_ERROR',
          details: {'error': error.toString()},
        );
      },
      onDone: () {
        emitFlowEvent(
          layer: 'FL',
          event: 'ORBIT_GROUP_MSG_STREAM_DONE',
          details: {},
        );
      },
    );
  }

  void _startListeningForChatMessages() {
    _chatSubscription = widget.chatMessageListener.incomingMessageStream.listen(
      (message) {
        if (!_isOrbitActive) {
          _dirtyFriendPeerIds.add(message.contactPeerId);
          return;
        }
        _enqueueOrbitFriendRefresh(message.contactPeerId);
      },
      onError: (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'ORBIT_CHAT_STREAM_ERROR',
          details: {'error': error.toString()},
        );
      },
      onDone: () {
        emitFlowEvent(
          layer: 'FL',
          event: 'ORBIT_CHAT_STREAM_DONE',
          details: {},
        );
      },
    );
  }

  /// 194: subscribe to conversation read-marking events so a lit unread node
  /// clears when the friend's messages are read from ANY surface — including
  /// ones with no orbit-owned nav hook (a notification-tap route pushed over the
  /// active Orbit tab, or a feed-side open). Active: refresh the friend now +
  /// emit a distinct ORBIT_FL_READ_REFRESH. Inactive: ride the existing
  /// `_dirtyFriendPeerIds` replay on the next rising edge. No-op when the repo
  /// is not a [ConversationReadEventSource].
  void _startListeningForReadEvents() {
    final repo = widget.messageRepo;
    if (repo is! ConversationReadEventSource) {
      return;
    }
    final readSource = repo as ConversationReadEventSource;
    _readSubscription = readSource.conversationReadStream.listen(
      (peerId) {
        if (!_isOrbitActive) {
          _dirtyFriendPeerIds.add(peerId);
          return;
        }
        unawaited(_refreshOrbitFriend(peerId));
        emitFlowEvent(
          layer: 'FL',
          event: 'ORBIT_FL_READ_REFRESH',
          details: {'peerId': peerId},
        );
      },
      onError: (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'ORBIT_READ_STREAM_ERROR',
          details: {'error': error.toString()},
        );
      },
      onDone: () {
        emitFlowEvent(
          layer: 'FL',
          event: 'ORBIT_READ_STREAM_DONE',
          details: {},
        );
      },
    );
  }

  void _startListeningForContactUpdates() {
    _contactUpdateSubscription = widget.chatMessageListener.contactUpdatedStream
        .listen(
          (contact) {
            if (!_isOrbitActive) {
              _dirtyFriendPeerIds.add(contact.peerId);
              return;
            }
            unawaited(_refreshOrbitFriend(contact.peerId));
          },
          onError: (error) {
            emitFlowEvent(
              layer: 'FL',
              event: 'ORBIT_CONTACT_UPDATE_STREAM_ERROR',
              details: {'error': error.toString()},
            );
          },
          onDone: () {
            emitFlowEvent(
              layer: 'FL',
              event: 'ORBIT_CONTACT_UPDATE_STREAM_DONE',
              details: {},
            );
          },
        );
  }

  void _startListeningForContactRequests() {
    _requestSubscription = widget.contactRequestListener.requestStream.listen(
      _onContactRequest,
      onError: (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'ORBIT_REQUEST_STREAM_ERROR',
          details: {'error': error.toString()},
        );
      },
      onDone: () {
        emitFlowEvent(
          layer: 'FL',
          event: 'ORBIT_REQUEST_STREAM_DONE',
          details: {},
        );
      },
    );
  }

  void _onContactRequest(ContactRequestModel request) {
    emitFlowEvent(
      layer: 'FL',
      event: 'ORBIT_FL_CONTACT_REQUEST_RECEIVED',
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
      requestRepo: widget.contactRequestRepo,
      contactRepo: widget.contactRepo,
      peerId: request.peerId,
      p2pService: widget.p2pService,
      identityRepo: widget.identityRepo,
      bridge: widget.bridge,
      onProfileDownloaded: widget.chatMessageListener.emitContactUpdate,
    );
    if (!mounted) return;
    if (result == AcceptContactRequestResult.success ||
        result == AcceptContactRequestResult.notPending) {
      _markContactChanged(request.peerId);
      await _refreshOrbitFriend(request.peerId);
      // 215: mirror the notification-tap accept — drop straight into the 1:1
      // chat for the newly-accepted peer so "say hi" is one tap, not three.
      final contact =
          await widget.contactRepo.getContact(request.peerId) ??
          request.toContactModel();
      if (!mounted) return;
      _openConversationForContact(contact);
    }
  }

  Future<void> _declineRequest(
    BuildContext ctx,
    ContactRequestModel request,
  ) async {
    Navigator.pop(ctx);
    await declineContactRequest(
      requestRepo: widget.contactRequestRepo,
      peerId: request.peerId,
    );
  }

  void _onScroll() {
    final offset = _scrollController.offset;
    final goingDown = offset > _lastScrollOffset && offset > 100;
    _lastScrollOffset = offset;

    if (!_searchActive) {
      final shouldShow = !goingDown || offset < 50;
      if (shouldShow != _isSearchTriggerVisible) {
        _isSearchTriggerVisible = shouldShow;
        if (shouldShow) {
          _searchTriggerController.forward();
        } else {
          _searchTriggerController.reverse();
        }
      }
    }
  }

  void _onSearchOpen() {
    _searchActive = true;
    _publishListProjection();
    _collapseController.animateTo(0, curve: _animCurve);
    _searchDockController.forward();
    _searchTriggerController.reverse();
    _searchFocusNode.requestFocus();
  }

  void _onSearchClose() {
    _searchFocusNode.unfocus();
    _searchController.clear();
    _searchActive = false;
    _searchQuery = '';
    _publishListProjection();
    _collapseController.animateTo(1.0, curve: _animCurve);
    _searchDockController.reverse();
    _searchTriggerController.forward();
  }

  void _onSearchChanged(String query) {
    _searchQuery = query;
    _publishListProjection();
  }

  void _onSearchClear() {
    _searchController.clear();
    _searchQuery = '';
    _publishListProjection();
    _searchFocusNode.requestFocus();
  }

  void _onFilterChanged(String tab) {
    _openRowNotifier.value = null;
    _filterTab = tab;
    _publishListProjection();
  }

  void _onIntroDockTap() {
    setState(() {
      _viewMode = OrbitViewMode.allChats;
    });
    _onFilterChanged('intros');
    emitFlowEvent(
      layer: 'FL',
      event: 'ORBIT_INTRO_DOCK_TAP',
      details: {},
    );
  }

  Future<void> _onIntroDockDismissed() async {
    final currentKeys = _currentReviewKeys();
    if (currentKeys.isEmpty) return;

    _seenReviewKeys = {..._seenReviewKeys, ...currentKeys};
    _publishListProjection();
    try {
      await widget.introReviewSeenRepository?.markAllSeen(currentKeys);
      emitFlowEvent(
        layer: 'FL',
        event: 'ORBIT_INTRO_DOCK_DISMISSED',
        details: {'count': currentKeys.length},
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ORBIT_INTRO_DOCK_DISMISS_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  // 193: flip the Orbit view surface. Leaving the all-chats view force-closes
  // search so its dock/trigger don't dangle over the Inner-Circle surface.
  void _onToggleView() {
    setState(() {
      if (_viewMode == OrbitViewMode.innerCircle) {
        _viewMode = OrbitViewMode.allChats;
      } else {
        if (_searchActive) {
          _onSearchClose();
        }
        _viewMode = OrbitViewMode.innerCircle;
      }
    });
  }

  Future<void> _onArchiveFriend(OrbitFriend friend) async {
    try {
      await archiveContact(
        contactRepo: widget.contactRepo,
        peerId: friend.peerId,
      );
      _markContactChanged(friend.peerId);
      await _refreshOrbitFriend(friend.peerId);
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ORBIT_FL_ARCHIVE_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _onUnarchiveFriend(OrbitFriend friend) async {
    try {
      await unarchiveContact(
        contactRepo: widget.contactRepo,
        peerId: friend.peerId,
      );
      _markContactChanged(friend.peerId);
      await _refreshOrbitFriend(friend.peerId);
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ORBIT_FL_UNARCHIVE_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _onBlockFriend(OrbitFriend friend) async {
    final confirmed = await showConfirmationDialog(
      context: context,
      title: AppLocalizations.of(context)!.orbit_block_title(friend.username),
      description:
          'They won\'t be able to send you messages. You can unblock them later.',
      confirmLabel: 'Block',
    );
    if (!confirmed || !mounted) return;

    try {
      await blockContact(
        contactRepo: widget.contactRepo,
        peerId: friend.peerId,
      );
      _openRowNotifier.value = null;
      _markContactChanged(friend.peerId);
      await _refreshOrbitFriend(friend.peerId);
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ORBIT_FL_BLOCK_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _onUnblockFriend(OrbitFriend friend) async {
    try {
      await unblockContact(
        contactRepo: widget.contactRepo,
        peerId: friend.peerId,
      );
      _markContactChanged(friend.peerId);
      await _refreshOrbitFriend(friend.peerId);
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ORBIT_FL_UNBLOCK_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _onDeleteFriend(OrbitFriend friend) async {
    final confirmed = await showConfirmationDialog(
      context: context,
      title: AppLocalizations.of(context)!.orbit_delete_chat,
      description:
          'This will permanently remove ${friend.username} and all messages. This cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (!confirmed || !mounted) return;

    try {
      await _deleteContactFromOrbit(friend.peerId);
      _openRowNotifier.value = null;
      _markContactChanged(friend.peerId);
      await _refreshOrbitFriend(friend.peerId);
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ORBIT_FL_DELETE_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  void _onFriendTap(OrbitFriend friend) {
    _openConversationForContact(friend.contact);
  }

  /// Opens the 1:1 [ConversationWired] for [contact], guarded against a
  /// double-push and restoring the post-close refresh on pop. Shared by the
  /// friend-row tap and the contact-request accept flow (215) so the deps
  /// block lives in exactly one place.
  void _openConversationForContact(ContactModel contact) {
    if (!mounted) return;
    if (!_openingFriendPeerIds.add(contact.peerId)) return;

    late final Future<Object?> pushedRoute;
    try {
      pushedRoute = Navigator.of(context).push(
        buildConversationRoute(
          builder: (_) => ConversationWired(
            contact: contact,
            identityRepo: widget.identityRepo,
            messageRepo: widget.messageRepo,
            chatMessageListener: widget.chatMessageListener,
            p2pService: widget.p2pService,
            bridge: widget.bridge,
            contactRepo: widget.contactRepo,
            mediaAttachmentRepo: widget.mediaAttachmentRepo,
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
            deleteContactFn: _deleteContactFromOrbit,
            appShellController: widget.appShellController,
          ),
        ),
      );
    } catch (_) {
      _openingFriendPeerIds.remove(contact.peerId);
      rethrow;
    }

    pushedRoute.whenComplete(() {
      _openingFriendPeerIds.remove(contact.peerId);
      if (!mounted) return;
      _markContactChanged(contact.peerId);
      unawaited(_refreshOrbitFriend(contact.peerId));
    });

    // Push first, then let the conversation route perform its own initial
    // read-marking without blocking the transition.
    unawaited(_markConversationReadInBackground(contact.peerId));
  }

  /// Opens the contact profile for [friend]; "Message" jumps into the chat.
  void _onFriendAvatarTap(OrbitFriend friend) {
    if (!mounted) return;
    ContactProfileScreen.open(
      context,
      contact: friend.contact,
      onMessage: () {
        Navigator.of(context).pop();
        _onFriendTap(friend);
      },
    );
  }

  Future<void> _deleteContactFromOrbit(String peerId) {
    return deleteContactAndMessages(
      contactRepo: widget.contactRepo,
      messageRepo: widget.messageRepo,
      peerId: peerId,
      mediaAttachmentRepo: widget.mediaAttachmentRepo,
      reactionRepo: widget.reactionRepository,
      mediaFileManager: widget.mediaFileManager,
      contactRequestRepo: widget.contactRequestRepo,
      introductionRepo: widget.introductionRepository,
    );
  }

  Future<void> _markConversationReadInBackground(String peerId) async {
    try {
      await markConversationRead(
        messageRepo: widget.messageRepo,
        contactPeerId: peerId,
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ORBIT_FL_MARK_READ_ERROR',
        details: {'peerId': peerId, 'error': e.toString()},
      );
    }
  }

  // 209: returns the push future (completes on pop) so the Settings-host
  // latch can single-flight the entry; still assignable where a VoidCallback
  // is expected (the display→scan cross-link).
  Future<void> _onMyQR() {
    return Navigator.of(context).push(
      buildConversationRoute(
        builder: (_) => QRDisplayWired(
          repo: widget.identityRepo,
          bridgeClient: widget.bridge,
          onClose: () => Navigator.of(context).pop(),
          onScanPressed: _onScanQR,
          backgroundPreference:
              widget.appShellController?.backgroundPreference ??
              BackgroundPreference.defaultBackground,
        ),
      ),
    );
  }

  Future<void> _applyRouteChanges(Object? result) async {
    final changes = result is FeedRouteChanges ? result : null;
    if (changes == null) return;

    if (changes.reloadAllContacts) {
      await _loadOrbitData();
    } else if (changes.changedContactPeerIds.isNotEmpty) {
      await Future.wait(changes.changedContactPeerIds.map(_refreshOrbitFriend));
    }

    if (changes.reloadAllGroups) {
      await _loadGroupData();
    } else if (changes.changedGroupIds.isNotEmpty) {
      await Future.wait(changes.changedGroupIds.map(_refreshOrbitGroup));
    }
  }

  void _attachExternalRouteChangesListenable(
    ValueListenable<FeedRouteChanges?>? listenable,
  ) {
    listenable?.addListener(_onExternalRouteChangesChanged);
  }

  void _detachExternalRouteChangesListenable(
    ValueListenable<FeedRouteChanges?>? listenable,
  ) {
    listenable?.removeListener(_onExternalRouteChangesChanged);
  }

  void _onExternalRouteChangesChanged() {
    final changes = widget.externalRouteChangesListenable?.value;
    if (changes == null) return;
    unawaited(_applyRouteChanges(changes));
  }

  // 209: same Future-returning contract as [_onMyQR]; the `.then` keeps the
  // post-scan `_applyRouteChanges` refresh and completes on scanner pop.
  Future<void> _onScanQR() {
    return Navigator.of(context)
        .push(
          buildConversationRoute(
            builder: (scannerContext) => QRScannerWired(
              bridge: widget.bridge,
              contactRepository: widget.contactRepo,
              contactRequestRepository: widget.contactRequestRepo,
              contactRequestListener: widget.contactRequestListener,
              messageRepository: widget.messageRepo,
              postRepository: widget.postRepository,
              mediaAttachmentRepository: widget.mediaAttachmentRepo,
              chatMessageListener: widget.chatMessageListener,
              identityRepository: widget.identityRepo,
              p2pService: widget.p2pService,
              mediaFileManager: widget.mediaFileManager,
              secureKeyStore: widget.secureKeyStore,
              imageProcessor: widget.imageProcessor,
              feedClearedRepository: widget.feedClearedRepository,
              ownPeerId: _identity?.peerId ?? '',
              conversationTracker: widget.conversationTracker,
              audioRecorderService: widget.audioRecorderService,
              reactionRepository: widget.reactionRepository,
              reactionListener: widget.reactionListener,
              groupRepository: widget.groupRepository,
              groupMessageRepository: widget.groupMessageRepository,
              groupReactionReplayOutboxRepository:
                  widget.groupReactionReplayOutboxRepository,
              groupMessageListener: widget.groupMessageListener,
              groupInviteListener: widget.groupInviteListener,
              waitForGroupMembershipUpdateIdle:
                  widget.waitForGroupMembershipUpdateIdle,
              groupConversationTracker: widget.groupConversationTracker,
              introductionRepository: widget.introductionRepository,
              introductionListener: widget.introductionListener,
              appShellController: widget.appShellController,
              pendingPostTargetStore: widget.pendingPostTargetStore,
              postsPrivacySettingsRepository:
                  widget.postsPrivacySettingsRepository,
              transportMetrics: widget.transportMetrics,
              accountMigrationRunTransfer: widget.accountMigrationRunTransfer,
              accountMigrationSizeGate: widget.accountMigrationSizeGate,
              onMigrationQrScanned: (qrData) async {
                emitFlowEvent(
                  layer: 'FL',
                  event: 'ORBIT_FL_MIGRATION_QR_DISPATCH',
                  details: {
                    'hasTransferRunner':
                        widget.accountMigrationRunTransfer != null,
                  },
                );
                if (!scannerContext.mounted) return;
                await Navigator.of(scannerContext).pushReplacement<void, void>(
                  buildConversationRoute(
                    builder: (_) => AccountMigrationJourneyWired.oldPhone(
                      secureKeyStore: widget.secureKeyStore,
                      identityRepository: widget.identityRepo,
                      runTransfer: widget.accountMigrationRunTransfer,
                      sizeGate: widget.accountMigrationSizeGate,
                      initialScannedQr: qrData,
                      backgroundPreference:
                          widget.appShellController?.backgroundPreference ??
                          BackgroundPreference.defaultBackground,
                    ),
                  ),
                );
              },
            ),
          ),
        )
        .then((result) => unawaited(_applyRouteChanges(result)));
  }

  void _onClose() {
    if (widget.onEmbeddedExit != null) {
      widget.appShellController?.switchTo(AppShellTab.feed);
      widget.onEmbeddedExit!(_buildRouteChanges());
      return;
    }
    Navigator.of(context).pop(_buildRouteChanges());
  }

  void _onSwitchView(String tab) {
    final appShellController = widget.appShellController;
    if (appShellController == null) {
      return;
    }

    if (tab == AppShellTab.feed) {
      if (widget.onEmbeddedExit != null) {
        _onClose();
        return;
      }
      appShellController.switchTo(AppShellTab.feed);
      _onClose();
      return;
    }

    appShellController.switchTo(tab);
  }

  @override
  void dispose() {
    _chatSubscription?.cancel();
    // 202: drop any pending coalesced refresh so its timer never fires after
    // teardown (TC-202-09d).
    _orbitRefreshCoalesceTimer?.cancel();
    _contactUpdateSubscription?.cancel();
    _requestSubscription?.cancel();
    _groupMessageSubscription?.cancel();
    _groupJoinedInviteSubscription?.cancel();
    _pendingGroupInviteSubscription?.cancel();
    _introReceivedSubscription?.cancel();
    _introStatusSubscription?.cancel();
    _readSubscription?.cancel();
    // 153: never commit a deferred decline after unmount (safe-failure = the
    // invite is kept; a re-mount re-surfaces it = implicit undo).
    for (final timer in _declineCommitTimers.values) {
      timer.cancel();
    }
    // 153 (review P1): dismiss the still-visible decline SnackBar so its Undo
    // action cannot be tapped after this State is gone (defensive: in
    // embeddings where the snackbar outlives the orbit Scaffold), and clear the
    // map so a stale tap finds no timer (the no-op guard holds).
    if (_declineCommitTimers.isNotEmpty) {
      _declineScaffoldMessenger?.hideCurrentSnackBar();
    }
    _declineCommitTimers.clear();
    _detachExternalRouteChangesListenable(
      widget.externalRouteChangesListenable,
    );
    _collapseAnimation.dispose();
    _searchDockAnimation.dispose();
    _searchTriggerAnimation.dispose();
    _collapseController.dispose();
    _searchDockController.dispose();
    _searchTriggerController.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _innerCircleResetTick.dispose();
    _openRowNotifier.removeListener(_onOpenRowNotifierChanged);
    widget.appShellController?.removeListener(_onAppShellChanged);
    widget.onEmbeddedExitActionChanged?.call(null);
    widget.onRowActionOpenChanged?.call(false);
    _openRowNotifier.dispose();
    _headerProjectionNotifier.dispose();
    _listProjectionNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showPersistentNav =
        widget.appShellController != null &&
        widget.feedUnreadCountListenable != null;
    return OrbitScreen(
      headerProjectionListenable: _headerProjectionNotifier,
      listProjectionListenable: _listProjectionNotifier,
      scrollController: _scrollController,
      searchController: _searchController,
      searchFocusNode: _searchFocusNode,
      collapseAnimation: _collapseAnimation,
      searchDockAnimation: _searchDockAnimation,
      searchTriggerAnimation: _searchTriggerAnimation,
      onClose: _onClose,
      onFriendTap: _onFriendTap,
      onFriendAvatarTap: _onFriendAvatarTap,
      onSearchOpen: _onSearchOpen,
      onSearchClose: _onSearchClose,
      onSearchChanged: _onSearchChanged,
      onSearchClear: _onSearchClear,
      onFilterChanged: _onFilterChanged,
      onArchiveFriend: _onArchiveFriend,
      onUnarchiveFriend: _onUnarchiveFriend,
      onBlockFriend: _onBlockFriend,
      onUnblockFriend: _onUnblockFriend,
      onDeleteFriend: _onDeleteFriend,
      openRowNotifier: _openRowNotifier,
      onGroupTap: _onGroupTap,
      onCreateGroup: _onCreateGroup,
      onArchiveGroup: _onArchiveGroup,
      onUnarchiveGroup: _onUnarchiveGroup,
      onDeleteGroup: _onDeleteGroup,
      onRetryStuckRejoinGroup: _onRetryStuckRejoinGroup,
      onLeaveStuckGroup: _onLeaveStuckGroup,
      viewMode: _viewMode,
      onToggleView: _onToggleView,
      hideShellNav: widget.hideShellNav,
      activeTab: showPersistentNav
          ? widget.appShellController!.activeTab
          : null,
      onSwitchView: showPersistentNav ? _onSwitchView : null,
      feedUnreadCountListenable: showPersistentNav
          ? widget.feedUnreadCountListenable
          : null,
      onIntroBannerTap: () => _onFilterChanged('intros'),
      onIntroDockTap: _onIntroDockTap,
      onIntroDockDismissed: _onIntroDockDismissed,
      onHeaderBuild: widget.debugOnHeaderBuild,
      onListBuild: widget.debugOnListBuild,
      backgroundPreference:
          widget.appShellController?.backgroundPreference ??
          BackgroundPreference.defaultBackground,
      secureKeyStore: widget.secureKeyStore,
      onInnerCircleEditSessionChanged: widget.onEditSessionActiveChanged,
      innerCircleResetListenable: _innerCircleResetTick,
      onSelfAvatarTap: _onSelfAvatarTap,
      p2pService: widget.p2pService,
    );
  }

  Future<void> _onArchiveGroup(OrbitGroup group) async {
    final groupRepository = widget.groupRepository;
    if (groupRepository == null) return;

    try {
      await archiveGroup(groupRepo: groupRepository, groupId: group.group.id);
      _markGroupChanged(group.group.id);
      await _refreshOrbitGroup(group.group.id);
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ORBIT_FL_ARCHIVE_GROUP_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _onUnarchiveGroup(OrbitGroup group) async {
    final groupRepository = widget.groupRepository;
    if (groupRepository == null) return;

    try {
      await unarchiveGroup(groupRepo: groupRepository, groupId: group.group.id);
      _markGroupChanged(group.group.id);
      await _refreshOrbitGroup(group.group.id);
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ORBIT_FL_UNARCHIVE_GROUP_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _onDeleteGroup(OrbitGroup group) async {
    final groupRepository = widget.groupRepository;
    final groupMessageRepository = widget.groupMessageRepository;
    if (groupRepository == null || groupMessageRepository == null) return;
    final isDissolved = group.group.isDissolved;

    final confirmed = await showConfirmationDialog(
      context: context,
      title: isDissolved
          ? 'Delete dissolved group?'
          : AppLocalizations.of(context)!.orbit_leave_group,
      description: isDissolved
          ? 'This will remove the dissolved group and its local history from this device. This cannot be undone.'
          : 'This will permanently leave the group and delete all messages. This cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (!confirmed || !mounted) return;

    try {
      await deleteGroupAndMessages(
        bridge: widget.bridge,
        groupRepo: groupRepository,
        groupMessageRepo: groupMessageRepository,
        groupId: group.group.id,
        deleteLocallyIfDissolved: true,
      );
      _openRowNotifier.value = null;
      _markGroupChanged(group.group.id);
      await _refreshOrbitGroup(group.group.id);
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ORBIT_FL_DELETE_GROUP_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  /// "Retry now" on a stuck (given-up) rejoin row: force the row eligible so the
  /// bounded retrier no longer skips it on backoff, kick a fresh rejoin pass,
  /// and refresh the row (G2). Never auto-deletes the group.
  Future<void> _onRetryStuckRejoinGroup(OrbitGroup group) async {
    final groupRepository = widget.groupRepository;
    if (groupRepository == null) return;
    try {
      await groupRepository.forceGroupRejoinEligible(group.group.id);
      await rejoinGroupTopics(
        bridge: widget.bridge,
        groupRepo: groupRepository,
        reason: RejoinReason.nodeRequestedRecovery,
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ORBIT_FL_STUCK_REJOIN_RETRY_ERROR',
        details: {'error': e.toString()},
      );
    } finally {
      _markGroupChanged(group.group.id);
      await _refreshOrbitGroup(group.group.id);
    }
  }

  /// "Leave" from a stuck rejoin row — a reachable exit from the dead-end (G2).
  /// Tears the group down via the normal leave path (never a silent auto-delete)
  /// and refreshes the row.
  Future<void> _onLeaveStuckGroup(OrbitGroup group) async {
    final groupRepository = widget.groupRepository;
    if (groupRepository == null) return;
    try {
      await leaveGroup(
        bridge: widget.bridge,
        groupRepo: groupRepository,
        groupId: group.group.id,
      );
      _openRowNotifier.value = null;
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ORBIT_FL_STUCK_LEAVE_ERROR',
        details: {'error': e.toString()},
      );
    } finally {
      _markGroupChanged(group.group.id);
      await _refreshOrbitGroup(group.group.id);
    }
  }

  void _onGroupTap(OrbitGroup group) {
    _openGroupConversationFromModel(group.group);
  }

  // Opens GroupConversationWired for a fully-committed GroupModel using the
  // exact arg set _onGroupTap uses, so an auto-opened chat (e.g. right after
  // accepting an invite) is configured identically to a manually-tapped one.
  void _openGroupConversationFromModel(GroupModel group) {
    final groupRepository = widget.groupRepository;
    final groupMessageRepository = widget.groupMessageRepository;
    final groupMessageListener = widget.groupMessageListener;
    if (groupRepository == null ||
        groupMessageRepository == null ||
        groupMessageListener == null) {
      return;
    }

    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => GroupConversationWired(
              group: group,
              groupRepo: groupRepository,
              msgRepo: groupMessageRepository,
              groupMessageListener: groupMessageListener,
              inviteDeliveryAttemptRepo:
                  widget.groupInviteDeliveryAttemptRepository,
              bridge: widget.bridge,
              identityRepo: widget.identityRepo,
              contactRepo: widget.contactRepo,
              p2pService: widget.p2pService,
              mediaAttachmentRepo: widget.mediaAttachmentRepo,
              mediaFileManager: widget.mediaFileManager,
              imageProcessor: widget.imageProcessor,
              qualityPreference: _qualityPreference,
              videoQualityPreference: _videoQualityPreference,
              audioRecorderService: widget.audioRecorderService,
              groupConversationTracker: widget.groupConversationTracker,
              reactionRepo: widget.reactionRepository,
              groupReactionReplayOutboxRepository:
                  widget.groupReactionReplayOutboxRepository,
              historyGapRepairRepo: widget.groupHistoryGapRepairRepository,
              backgroundPreference:
                  widget.appShellController?.backgroundPreference ??
                  BackgroundPreference.defaultBackground,
            ),
          ),
        )
        .then((_) {
          _markGroupChanged(group.id);
          unawaited(_refreshOrbitGroup(group.id));
        });
  }

  void _onCreateGroup(GroupType type) {
    final groupRepository = widget.groupRepository;
    final groupMessageRepository = widget.groupMessageRepository;
    final groupMessageListener = widget.groupMessageListener;
    if (groupRepository == null ||
        groupMessageRepository == null ||
        groupMessageListener == null) {
      return;
    }

    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => CreateGroupPickerWired(
              groupType: type,
              groupRepo: groupRepository,
              msgRepo: groupMessageRepository,
              groupMessageListener: groupMessageListener,
              inviteDeliveryAttemptRepo:
                  widget.groupInviteDeliveryAttemptRepository,
              contactRepo: widget.contactRepo,
              bridge: widget.bridge,
              identityRepo: widget.identityRepo,
              p2pService: widget.p2pService,
              groupConversationTracker: widget.groupConversationTracker,
              mediaAttachmentRepo: widget.mediaAttachmentRepo,
              mediaFileManager: widget.mediaFileManager,
              imageProcessor: widget.imageProcessor,
              qualityPreference: _qualityPreference,
              videoQualityPreference: _videoQualityPreference,
              audioRecorderService: widget.audioRecorderService,
              reactionRepo: widget.reactionRepository,
              groupReactionReplayOutboxRepository:
                  widget.groupReactionReplayOutboxRepository,
              backgroundPreference:
                  widget.appShellController?.backgroundPreference ??
                  BackgroundPreference.defaultBackground,
            ),
          ),
        )
        .then((result) => unawaited(_applyRouteChanges(result)));
  }
}
