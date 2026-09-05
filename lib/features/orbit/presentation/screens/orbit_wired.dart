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
import 'package:flutter_app/core/widgets/undo_bar.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_transfer_flow.dart';
import 'package:flutter_app/features/account_migration/application/migration_account_size_estimator.dart';
import 'package:flutter_app/features/account_migration/presentation/screens/account_migration_journey_wired.dart';
import 'package:flutter_app/features/contact_request/application/accept_and_reciprocate_use_case.dart';
import 'package:flutter_app/features/contact_request/application/send_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/application/accept_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contact_request/application/decline_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/contact_request/domain/repositories/contact_request_repository.dart';
import 'package:flutter_app/features/contacts/application/direct_contact_device_trust.dart';
import 'package:flutter_app/features/qr_code/application/direct_linked_device_qr.dart';
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
import 'package:flutter_app/features/conversation/presentation/screens/direct_conversation_route_authority.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/home/application/identity_avatar_resolver.dart';
import 'package:flutter_app/features/contacts/application/archive_contact_use_case.dart';
import 'package:flutter_app/features/groups/application/archive_group_use_case.dart';
import 'package:flutter_app/features/groups/application/change_group_member_role_and_broadcast_use_case.dart';
import 'package:flutter_app/features/groups/application/delete_self_removed_group_shell_use_case.dart';
import 'package:flutter_app/features/groups/application/dissolve_group_use_case.dart';
import 'package:flutter_app/features/groups/application/group_dissolve_preflight_sink.dart';
import 'package:flutter_app/features/groups/application/group_exit_intent_coordinator.dart';
import 'package:flutter_app/features/groups/application/group_exit_intent_sink.dart';
import 'package:flutter_app/features/groups/application/group_exit_policy.dart';
import 'package:flutter_app/features/groups/application/group_exit_terminal_diagnostics.dart';
import 'package:flutter_app/features/groups/application/group_media_delete_for_me_coordinator.dart';
import 'package:flutter_app/features/groups/application/group_pending_broadcast_sink.dart';
import 'package:flutter_app/features/groups/application/group_sender_device_binding.dart';
import 'package:flutter_app/features/groups/application/unarchive_group_use_case.dart';
import 'package:flutter_app/features/groups/application/delete_group_and_messages_use_case.dart';
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
import 'package:flutter_app/features/groups/application/retry_incomplete_group_downloads_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_exit_diagnostic.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/application/group_invite_listener.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_broadcast.dart';
import 'package:flutter_app/features/groups/domain/models/group_welcome_key_package.dart';
import 'package:flutter_app/features/groups/domain/models/pending_group_invite.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_exit_diagnostic_repository.dart';
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
import 'package:flutter_app/features/groups/presentation/group_exit_diagnostic_presenter.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_wired.dart';
import 'package:flutter_app/features/groups/presentation/widgets/pending_group_invite_card.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_exit_recovery_sheet.dart';
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
  final GroupExitDiagnosticRepository? groupExitDiagnosticRepository;
  final GroupInviteDeliveryAttemptRepository?
  groupInviteDeliveryAttemptRepository;
  final GroupPendingKeyRepairRepository? groupPendingKeyRepairRepository;
  final GroupHistoryGapRepairRepository? groupHistoryGapRepairRepository;
  final GroupReactionReplayOutboxRepository?
  groupReactionReplayOutboxRepository;
  final DeleteSelfRemovedGroupShellCallback? deleteSelfRemovedGroupShell;

  /// Explicit fixture-only override. Production resolves through the installed
  /// diagnosing action adapter.
  final ResolveGroupExitActionSnapshot? resolveGroupExitSnapshotForTest;

  /// 235: production Delete-for-me coordinator, threaded into every group
  /// conversation this shell opens. Null keeps the action hidden.
  final GroupMediaDeleteForMeCoordinator? groupMediaDeleteForMeCoordinator;
  final GroupMessageListener? groupMessageListener;
  final GroupMediaDownloadCoordinator? groupMediaDownloadCoordinator;
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
  final ResolveCallWakeHandle? resolveCallWakeHandle;
  final OnCallWakeHandleDistributed? onCallWakeHandleDistributed;

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

  /// 362: the one linked-device authority for conversations, contact trust,
  /// and QR staging in this shell. Null preserves incumbent behavior.
  final DirectConversationRouteAuthority? directRouteAuthority;

  const OrbitWired({
    super.key,
    this.directRouteAuthority,
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
    this.groupExitDiagnosticRepository,
    this.groupInviteDeliveryAttemptRepository,
    this.groupPendingKeyRepairRepository,
    this.groupHistoryGapRepairRepository,
    this.groupReactionReplayOutboxRepository,
    this.deleteSelfRemovedGroupShell,
    this.resolveGroupExitSnapshotForTest,
    this.groupMediaDeleteForMeCoordinator,
    this.groupMessageListener,
    this.groupMediaDownloadCoordinator,
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
    this.resolveCallWakeHandle,
    this.onCallWakeHandleDistributed,
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
  StreamSubscription<String>? _groupReadSubscription;
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
  // per-invite [UndoBarHandle] commits on timeout (Undo / dispose cancels it
  // first).
  final Set<String> _optimisticallyDeclinedInviteIds = <String>{};
  final Map<String, UndoBarHandle> _declineUndoBars = <String, UndoBarHandle>{};
  final Map<String, PendingInviteRowOutcome> _inviteRowOutcomes =
      <String, PendingInviteRowOutcome>{};
  Set<String> _askNewInviteIds = <String>{};
  Set<String> _unavailableInviteContactIds = <String>{};
  int _inviteRequestQualificationEpoch = 0;
  final Set<String> _openingFriendPeerIds = <String>{};
  Set<String> _blockedPeerIds = {};
  final Set<String> _changedContactPeerIds = <String>{};
  final Set<String> _changedGroupIds = <String>{};
  bool _refreshPendingIntroductionsOnPop = false;
  int _introLoadRequestId = 0;
  bool _isGroupExitInFlight = false;
  Set<String> _exitIntentGroupIds = <String>{};

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
    final pendingInviteIds = _pendingGroupInvites
        .map((invite) => invite.groupId)
        .toSet();
    final ghostInviteCount = _inviteRowOutcomes.keys
        .where((id) => !pendingInviteIds.contains(id))
        .length;
    final inviteReviewCount = _pendingGroupInvites.length + ghostInviteCount;

    return OrbitViewProjection(
      allFriends: List<OrbitFriend>.unmodifiable(_activeFriends),
      displayedFriends: List<OrbitFriend>.unmodifiable(displayedFriends),
      groups: List<OrbitGroup>.unmodifiable(groups),
      mergedItems: List<OrbitItem>.unmodifiable(mergedItems),
      activeCount: _activeFriends.length + _activeGroups.length,
      archivedCount: _archivedFriends.length + _archivedGroups.length,
      introCount: _introsCount,
      pendingGroupInviteCount: inviteReviewCount,
      reviewCount: _introsCount + inviteReviewCount,
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
        inviteRowOutcomes: Map<String, PendingInviteRowOutcome>.unmodifiable(
          _inviteRowOutcomes,
        ),
        askNewInviteIds: Set<String>.unmodifiable(_askNewInviteIds),
        unavailableInviteContactIds: Set<String>.unmodifiable(
          _unavailableInviteContactIds,
        ),
        processingIntroductionIds: _processingIntroductionIds,
        processingPendingInviteIds: _processingPendingInviteIds,
        onAccept: _onAcceptIntro,
        onPass: _onPassIntro,
        onDelete: _onDeleteIntro,
        onSendMessage: _onIntroSendMessage,
        onAcceptPendingInvite: _onAcceptPendingInvite,
        onDeclinePendingInvite: _onDeclinePendingInvite,
        onRetryPendingInvite: _onAcceptPendingInvite,
        onAskForNewInvite: _onAskForNewInvite,
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
      for (final inviteId in _inviteRowOutcomes.keys)
        introReviewKeyForGroupInvite(inviteId),
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
    _collapseAnimation = CurvedAnimation(
      parent: _collapseController,
      curve: _animCurve,
    );
    _searchDockAnimation = CurvedAnimation(
      parent: _searchDockController,
      curve: _animCurve,
    );
    _searchTriggerAnimation = CurvedAnimation(
      parent: _searchTriggerController,
      curve: Curves.ease,
    );

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
    _startListeningForGroupReadEvents();
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
  static const Duration _orbitRefreshCoalesceWindow = Duration(
    milliseconds: 32,
  );

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
              groupExitDiagnosticRepository:
                  widget.groupExitDiagnosticRepository,
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
              mediaStorageManager:
                  widget.mediaStorageManager ??
                  MediaStorageManager(
                    repository: widget.mediaAttachmentRepo,
                    documentsDirectoryProvider: () async =>
                        (await getApplicationDocumentsDirectory()).path,
                  ),
              mediaStorageScopesProvider:
                  widget.mediaStorageScopesProvider ?? _loadMediaStorageScopes,
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

    final exitIntents = await loadAllGroupExitIntents();
    if (exitIntents.isAvailable) {
      _exitIntentGroupIds = exitIntents.intents
          .map((intent) => intent.groupId)
          .toSet();
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
              hasExitIntent: _exitIntentGroupIds.contains(group.groupId),
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
      _archivedGroups = archived
          .map(
            (group) => group.copyWith(
              hasExitIntent: _exitIntentGroupIds.contains(group.groupId),
            ),
          )
          .toList();
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
        unawaited(_refreshInviteRequestAvailability());
      }
      return;
    }

    try {
      final invites = await inviteListener.pendingInviteRepo
          .getPendingInvites();
      final currentMemberGroupIds = await _loadCurrentMemberGroupIds(
        invites.map((invite) => invite.groupId),
      );
      if (!mounted) return;
      // Current membership is repository authority, not the concurrently
      // hydrated Orbit projection. A pending load may finish before
      // [_loadGroupData], and a stale card must not win that race.
      _pendingGroupInvites = invites
          .where(
            (invite) =>
                !currentMemberGroupIds.contains(invite.groupId) &&
                // 153: keep optimistically-declined rows hidden across every
                // reactive reload until their deferred commit/undo resolves.
                !_optimisticallyDeclinedInviteIds.contains(invite.groupId),
          )
          .toList();
      _publishListProjection();
      unawaited(_refreshInviteRequestAvailability());
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ORBIT_FL_LOAD_PENDING_GROUP_INVITES_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<Set<String>> _loadCurrentMemberGroupIds(
    Iterable<String> groupIds,
  ) async {
    final groupRepository = widget.groupRepository;
    if (groupRepository == null) return const <String>{};

    String? peerId;
    try {
      peerId = (await widget.identityRepo.loadIdentity())?.peerId.trim();
    } catch (_) {
      return const <String>{};
    }
    if (peerId == null || peerId.isEmpty) return const <String>{};

    final current = <String>{};
    for (final groupId in groupIds.toSet()) {
      try {
        if (await groupRepository.getMember(groupId, peerId) != null) {
          current.add(groupId);
        }
      } catch (_) {
        // A failed authority read keeps the invite visible and actionable via
        // the incumbent path; it never fabricates current membership.
      }
    }
    return current;
  }

  Future<({bool isCurrentMember, GroupModel? group})> _loadCurrentMembership(
    String groupId,
  ) async {
    final groupRepository = widget.groupRepository;
    if (groupRepository == null) {
      return (isCurrentMember: false, group: null);
    }
    String? peerId;
    try {
      peerId = (await widget.identityRepo.loadIdentity())?.peerId.trim();
      if (peerId == null || peerId.isEmpty) {
        return (isCurrentMember: false, group: null);
      }
      final member = await groupRepository.getMember(groupId, peerId);
      if (member == null) {
        return (isCurrentMember: false, group: null);
      }
    } catch (_) {
      return (isCurrentMember: false, group: null);
    }

    // Membership is the action authority. A later presentation-model lookup
    // may fail, but that must only prevent navigation; it cannot downgrade a
    // confirmed member and re-enable stale invite actions.
    GroupModel? group;
    try {
      group = await groupRepository.getGroup(groupId);
    } catch (_) {
      group = null;
    }
    return (isCurrentMember: true, group: group);
  }

  void _purgeCurrentMemberInviteState(String groupId) {
    _declineUndoBars.remove(groupId)?.cancel();
    _optimisticallyDeclinedInviteIds.remove(groupId);
    _pendingGroupInvites = _pendingGroupInvites
        .where((invite) => invite.groupId != groupId)
        .toList();
    _inviteRowOutcomes.remove(groupId);
    _askNewInviteIds.remove(groupId);
    _unavailableInviteContactIds.remove(groupId);
    _publishListProjection();
    unawaited(_refreshInviteRequestAvailability());
  }

  Future<bool> _handleCurrentMemberInvite(
    String groupId, {
    required bool openGroup,
  }) async {
    final membership = await _loadCurrentMembership(groupId);
    if (!membership.isCurrentMember || !mounted) return false;
    _purgeCurrentMemberInviteState(groupId);
    final group = membership.group;
    if (openGroup && group != null) {
      _openGroupConversationFromModel(group);
    }
    return true;
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
    _orbitRefreshCoalesceTimer ??= Timer(
      _orbitRefreshCoalesceWindow,
      _flushOrbitRefreshes,
    );
  }

  void _enqueueOrbitGroupRefresh(String groupId) {
    _pendingGroupRefreshGroupIds.add(groupId);
    _orbitRefreshCoalesceTimer ??= Timer(
      _orbitRefreshCoalesceWindow,
      _flushOrbitRefreshes,
    );
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
      final exitIntent = await loadGroupExitIntent(groupId);
      if (!mounted) return;

      OrbitGroup? previous;
      for (final entry in [..._activeGroups, ..._archivedGroups]) {
        if (entry.groupId == groupId) {
          previous = entry;
          break;
        }
      }

      final refreshed = group?.copyWith(
        rejoinAttemptCount: rejoinStates[groupId]?.attemptCount,
        hasExitIntent: exitIntent.isAvailable
            ? exitIntent.intent != null
            : previous?.hasExitIntent ?? false,
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
        // The joined event is already authoritative. Purge stale invite rows,
        // outcomes, and Ask-new state synchronously before either refresh can
        // race a cached projection back onto the screen.
        _purgeCurrentMemberInviteState(group.id);
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

    setState(() {
      _processingPendingInviteIds.add(invite.groupId);
      _inviteRowOutcomes.remove(invite.groupId);
      _askNewInviteIds.remove(invite.groupId);
      _unavailableInviteContactIds.remove(invite.groupId);
    });
    _publishListProjection();
    try {
      if (await _handleCurrentMemberInvite(invite.groupId, openGroup: true)) {
        return;
      }
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
      if (result != AcceptPendingGroupInviteResult.success &&
          await _handleCurrentMemberInvite(invite.groupId, openGroup: true)) {
        return;
      }
      switch (result) {
        case AcceptPendingGroupInviteResult.success:
          inviteListener.scheduleGroupInviteRetirement?.call(
            groupId: invite.groupId,
            inviteId: invite.inviteId,
          );
          // 208: navigating accept — open the group chat with NO confirmation
          // snackbar.
          if (group != null && mounted) {
            _openGroupConversationFromModel(group);
          }
          break;
        case AcceptPendingGroupInviteResult.notFound:
          _setTerminalInviteOutcome(
            invite,
            l10n.group_invite_no_longer_available,
          );
          break;
        case AcceptPendingGroupInviteResult.expired:
          _setTerminalInviteOutcome(invite, l10n.group_invite_expired);
          break;
        case AcceptPendingGroupInviteResult.expiredFreshness:
          _setTerminalInviteOutcome(
            invite,
            l10n.group_invite_expired_ask_resend,
          );
          break;
        case AcceptPendingGroupInviteResult.revoked:
          _setTerminalInviteOutcome(invite, l10n.group_invite_revoked);
          break;
        case AcceptPendingGroupInviteResult.alreadyUsed:
          _setTerminalInviteOutcome(invite, l10n.group_invite_already_used);
          break;
        case AcceptPendingGroupInviteResult.wrongIdentity:
          _setTerminalInviteOutcome(invite, l10n.group_invite_wrong_identity);
          break;
        case AcceptPendingGroupInviteResult.repairPending:
          _setInviteRowOutcome(invite, PendingInviteRowState.waitingForKey);
          break;
        case AcceptPendingGroupInviteResult.invalidPayload:
          _setTerminalInviteOutcome(invite, l10n.group_invite_invalid);
          break;
        case AcceptPendingGroupInviteResult.duplicateGroup:
          _setTerminalInviteOutcome(invite, l10n.group_invite_duplicate_group);
          break;
        case AcceptPendingGroupInviteResult.bridgeError:
          if (group != null) {
            _openGroupConversationFromModel(group);
          } else {
            _setInviteRowOutcome(
              invite,
              PendingInviteRowState.retryable,
              reason: l10n.group_invite_accept_failed,
            );
          }
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
      if (!mounted) return;
      if (await _handleCurrentMemberInvite(invite.groupId, openGroup: true)) {
        return;
      }
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      _setInviteRowOutcome(
        invite,
        PendingInviteRowState.retryable,
        reason: l10n.group_invite_accept_failed,
      );
    } finally {
      if (mounted) {
        setState(() => _processingPendingInviteIds.remove(invite.groupId));
        _publishListProjection();
      }
    }
  }

  void _setInviteRowOutcome(
    PendingGroupInvite invite,
    PendingInviteRowState state, {
    String? reason,
  }) {
    if (!mounted) return;
    _inviteRowOutcomes[invite.groupId] = PendingInviteRowOutcome(
      state: state,
      groupName: invite.groupName,
      reason: reason,
      inviterPeerId: invite.senderPeerId,
      inviterUsername: invite.senderUsername,
    );
    _publishListProjection();
    unawaited(_refreshInviteRequestAvailability());
  }

  void _setTerminalInviteOutcome(PendingGroupInvite invite, String reason) {
    _setInviteRowOutcome(invite, PendingInviteRowState.idle, reason: reason);
  }

  Map<String, _OrbitInviteRequestTarget> _inviteRequestTargets() {
    final now = DateTime.now().toUtc();
    final liveIds = _pendingGroupInvites
        .map((invite) => invite.groupId)
        .toSet();
    final targets = <String, _OrbitInviteRequestTarget>{};
    for (final invite in _pendingGroupInvites) {
      if (invite.isExpiredAt(now) && invite.senderPeerId.isNotEmpty) {
        targets[invite.groupId] = _OrbitInviteRequestTarget(
          peerId: invite.senderPeerId,
          groupName: invite.groupName,
        );
      }
    }
    for (final entry in _inviteRowOutcomes.entries) {
      if (liveIds.contains(entry.key)) continue;
      final peerId = entry.value.inviterPeerId;
      if (peerId != null && peerId.isNotEmpty) {
        targets[entry.key] = _OrbitInviteRequestTarget(
          peerId: peerId,
          groupName: entry.value.groupName,
        );
      }
    }
    return targets;
  }

  bool _isQualifiedInviteContact(ContactModel? contact, String peerId) {
    return contact != null &&
        contact.peerId == peerId &&
        !contact.isBlocked &&
        !contact.isArchived;
  }

  Future<void> _refreshInviteRequestAvailability() async {
    final epoch = ++_inviteRequestQualificationEpoch;
    final targets = _inviteRequestTargets();
    final eligible = <String>{};
    for (final entry in targets.entries) {
      ContactModel? contact;
      try {
        contact = await widget.contactRepo.getContact(entry.value.peerId);
      } catch (_) {
        contact = null;
      }
      if (_isQualifiedInviteContact(contact, entry.value.peerId)) {
        eligible.add(entry.key);
      }
    }
    if (!mounted || epoch != _inviteRequestQualificationEpoch) return;
    _askNewInviteIds = eligible;
    _unavailableInviteContactIds = _unavailableInviteContactIds.intersection(
      targets.keys.toSet(),
    )..removeAll(eligible);
    _publishListProjection();
  }

  Future<void> _onAskForNewInvite(String inviteId) async {
    final target = _inviteRequestTargets()[inviteId];
    if (target == null) return;

    if (await _handleCurrentMemberInvite(inviteId, openGroup: false)) {
      return;
    }

    ContactModel? contact;
    try {
      contact = await widget.contactRepo.getContact(target.peerId);
    } catch (_) {
      contact = null;
    }
    if (!mounted) return;
    if (!_isQualifiedInviteContact(contact, target.peerId)) {
      _askNewInviteIds.remove(inviteId);
      _unavailableInviteContactIds.add(inviteId);
      _publishListProjection();
      return;
    }
    // Contact qualification is asynchronous. Membership may converge while
    // it is in flight, so make the authority check immediately before opening
    // the draft rather than relying on the tap-time preflight alone.
    if (await _handleCurrentMemberInvite(inviteId, openGroup: false)) {
      return;
    }
    if (!mounted) return;

    final initialText = AppLocalizations.of(
      context,
    )!.group_invite_request_new_draft(target.groupName);
    await _openConversationForContact(contact!, initialText: initialText);
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
    _inviteRowOutcomes.remove(invite.groupId);
    _askNewInviteIds.remove(invite.groupId);
    _unavailableInviteContactIds.remove(invite.groupId);
    _pendingGroupInvites = _pendingGroupInvites
        .where((i) => !_optimisticallyDeclinedInviteIds.contains(i.groupId))
        .toList();
    _refreshPendingIntroductionsOnPop = true;
    _publishListProjection();

    final l10n = AppLocalizations.of(context)!;
    _declineUndoBars[invite.groupId] = showUndoBar(
      context,
      message: l10n.group_invite_declined,
      window: kDeclineUndoWindow,
      onUndo: () => _undoDecline(invite),
      onCommit: () => _commitDecline(invite),
    );
  }

  /// Cancel a pending decline before its window elapses: re-surface the invite,
  /// emit UNDONE, and never send the decline-ack. The shared handle invokes
  /// this callback only while the Undo authority is still active.
  void _undoDecline(PendingGroupInvite invite) {
    if (!mounted) return;
    _declineUndoBars.remove(invite.groupId);
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
    unawaited(_loadPendingGroupInvites());
  }

  /// Fire the deferred decline once the undo window elapses. Runs the real
  /// (already-idempotent) use-case, then in `finally` releases the optimistic
  /// hide + processing guard and reloads — so a throwing commit re-surfaces the
  /// still-present invite, while a successful commit keeps it gone.
  Future<void> _commitDecline(PendingGroupInvite invite) async {
    _declineUndoBars.remove(invite.groupId);
    if (await _handleCurrentMemberInvite(invite.groupId, openGroup: false)) {
      _optimisticallyDeclinedInviteIds.remove(invite.groupId);
      _processingPendingInviteIds.remove(invite.groupId);
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }
      return;
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
      final isCurrentMember = await _handleCurrentMemberInvite(
        invite.groupId,
        openGroup: false,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        if (!isCurrentMember) {
          final l10n = AppLocalizations.of(context)!;
          if (error != null) {
            _setInviteRowOutcome(
              invite,
              PendingInviteRowState.idle,
              reason: l10n.group_invite_decline_failed,
            );
          } else if (result != null) {
            switch (result) {
              case DeclinePendingGroupInviteResult.success:
                _setTerminalInviteOutcome(invite, l10n.group_invite_declined);
                break;
              case DeclinePendingGroupInviteResult.notFound:
                _setTerminalInviteOutcome(
                  invite,
                  l10n.group_invite_no_longer_available,
                );
                break;
              case DeclinePendingGroupInviteResult.expired:
                _setTerminalInviteOutcome(invite, l10n.group_invite_expired);
                break;
            }
          }
        }
      }
    }
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

  /// Refreshes one group node after a real conversation read commit, including
  /// notification-owned routes that bypass Orbit's group navigation callback.
  /// Off-screen events reuse the existing dirty-group replay on the next Orbit
  /// rising edge so background tabs do not rebuild eagerly.
  void _startListeningForGroupReadEvents() {
    final repo = widget.groupMessageRepository;
    if (repo is! GroupConversationReadEventSource) {
      return;
    }
    final readSource = repo as GroupConversationReadEventSource;
    _groupReadSubscription = readSource.groupConversationReadStream.listen(
      (groupId) {
        if (!_isOrbitActive) {
          _dirtyGroupIds.add(groupId);
          return;
        }
        unawaited(_refreshOrbitGroup(groupId));
        emitFlowEvent(
          layer: 'FL',
          event: 'ORBIT_FL_GROUP_READ_REFRESH',
          details: {'groupId': groupId},
        );
      },
      onError: (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'ORBIT_GROUP_READ_STREAM_ERROR',
          details: {'error': error.toString()},
        );
      },
      onDone: () {
        emitFlowEvent(
          layer: 'FL',
          event: 'ORBIT_GROUP_READ_STREAM_DONE',
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
      resolveCallWakeHandle: widget.resolveCallWakeHandle,
      onCallWakeHandleDistributed: widget.onCallWakeHandleDistributed,
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
      unawaited(_openConversationForContact(contact));
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
    emitFlowEvent(layer: 'FL', event: 'ORBIT_INTRO_DOCK_TAP', details: {});
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
    unawaited(_openConversationForContact(friend.contact));
  }

  /// Opens the 1:1 [ConversationWired] for [contact], guarded against a
  /// double-push and restoring the post-close refresh on pop. Shared by the
  /// friend-row tap and the contact-request accept flow (215) so the deps
  /// block lives in exactly one place.
  Future<void> _openConversationForContact(
    ContactModel contact, {
    String? initialText,
  }) async {
    if (!mounted) return;
    if (!_openingFriendPeerIds.add(contact.peerId)) return;

    try {
      final pushedRoute = Navigator.of(context).push(
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
            initialText: initialText,
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
      // Push first, then let the conversation route perform its own initial
      // read-marking without blocking the transition.
      unawaited(_markConversationReadInBackground(contact.peerId));
      await pushedRoute;
    } finally {
      _openingFriendPeerIds.remove(contact.peerId);
      if (mounted) {
        _markContactChanged(contact.peerId);
        unawaited(_refreshOrbitFriend(contact.peerId));
      }
    }
  }

  /// Opens the contact profile for [friend]; "Message" jumps into the chat.
  void _onFriendAvatarTap(OrbitFriend friend) {
    if (!mounted) return;
    ContactProfileScreen.open(
      context,
      contact: friend.contact,
      directDeviceTrust:
          widget.directRouteAuthority.resolvedDirectDeviceTrust ??
          const UnavailableDirectContactDeviceTrust(),
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
  /// 360: authenticates a scanned linked-device document for an EXISTING
  /// contact and stages exactly one `pending` binding.
  ///
  /// Everything admission-related stays where it already lives: the parser owns
  /// authentication (dual signatures, both peer derivations, canonical UTC age
  /// and skew, known non-blocked contact, byte-equal stored account material),
  /// the repository owns the transactional stage, and explicit Verify/Reject on
  /// the contact profile owns admission. This wiring adds no new authority — it
  /// only makes the existing owners reachable from the trust flow.
  Future<void> _stageScannedLinkedDeviceQr(
    BuildContext scannerContext,
    String qrData,
  ) async {
    final trust = widget.directRouteAuthority.resolvedDirectDeviceTrust;
    if (trust == null) return;
    final (result, document) = await parseDirectLinkedDeviceQr(
      qrString: qrData,
      ownAccountPeerId: _identity?.peerId ?? '',
      lookupContact: widget.contactRepo.getContact,
      callVerify:
          ({
            required String publicKey,
            required String data,
            required String signature,
          }) => callVerifyPayload(
            bridge: widget.bridge,
            publicKey: publicKey,
            data: data,
            signature: signature,
          ),
    );
    emitFlowEvent(
      layer: 'FL',
      event: 'DIRECT_LINKED_DEVICE_SCAN_RESULT',
      details: {'result': result.name},
    );
    if (result != ParseDirectLinkedDeviceQrResult.success || document == null) {
      return;
    }
    await trust.stagePendingBinding(document);
  }

  Future<void> _onScanQR() {
    return Navigator.of(context)
        .push(
          buildConversationRoute(
            builder: (scannerContext) => QRScannerWired(
              directRouteAuthority: widget.directRouteAuthority,
              resolveCallWakeHandle: widget.resolveCallWakeHandle,
              onCallWakeHandleDistributed: widget.onCallWakeHandleDistributed,
              // 360: the known-contact linked-device scan action. Supplying it
              // here is what makes the dedicated dual-signed document reach the
              // trust flow instead of being refused as invalid; the handler
              // itself still requires the default-off selector, an existing
              // non-blocked contact, and byte-equal stored account material,
              // and it stages PENDING authority only.
              onDirectLinkedDeviceQrScanned: (qrData) =>
                  _stageScannedLinkedDeviceQr(scannerContext, qrData),
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
              groupExitDiagnosticRepository:
                  widget.groupExitDiagnosticRepository,
              groupReactionReplayOutboxRepository:
                  widget.groupReactionReplayOutboxRepository,
              groupMessageListener: widget.groupMessageListener,
              groupMediaDownloadCoordinator:
                  widget.groupMediaDownloadCoordinator,
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
    _groupReadSubscription?.cancel();
    // 153: never commit a deferred decline after unmount (safe-failure = the
    // invite is kept; a re-mount re-surfaces it = implicit undo).
    for (final bar in _declineUndoBars.values) {
      bar.cancel();
    }
    _declineUndoBars.clear();
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
      onLeaveGroup: _onLeaveGroup,
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

  Future<GroupExitSnapshot?> _resolveFreshGroupExit(String groupId) async {
    final groupRepository = widget.groupRepository;
    if (groupRepository == null) return null;
    try {
      final fixtureResolve = widget.resolveGroupExitSnapshotForTest;
      return fixtureResolve == null
          ? await resolveGroupExitActionSnapshot(groupId)
          : await fixtureResolve(groupId);
    } catch (_) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ORBIT_FL_GROUP_EXIT_CLASSIFY_ERROR',
        details: const {
          'code': 'EX01',
          'phase': 'authority',
          'severity': 'failure',
        },
      );
      if (mounted) {
        _showSnackBar(AppLocalizations.of(context)!.group_info_leave_failed);
      }
      return null;
    }
  }

  Future<void> _onLeaveGroup(OrbitGroup group) async {
    if (_isGroupExitInFlight) return;
    _isGroupExitInFlight = true;
    try {
      final snapshot = await _resolveFreshGroupExit(group.group.id);
      if (!mounted || snapshot == null) return;
      if (snapshot.group == null) {
        _markGroupChanged(group.group.id);
        await _refreshOrbitGroup(group.group.id);
        return;
      }
      await _dispatchFreshGroupExit(snapshot, confirmNormalLeave: true);
    } finally {
      _isGroupExitInFlight = false;
    }
  }

  Future<void> _onDeleteGroup(OrbitGroup group) async {
    if (_isGroupExitInFlight) return;
    _isGroupExitInFlight = true;
    try {
      final snapshot = await _resolveFreshGroupExit(group.group.id);
      if (!mounted || snapshot == null) return;
      if (snapshot.group == null) {
        _markGroupChanged(group.group.id);
        await _refreshOrbitGroup(group.group.id);
        return;
      }
      // A stale dissolved row may have become active (or vice versa). Dispatch
      // from fresh state rather than trusting the swipe's captured OrbitGroup.
      await _dispatchFreshGroupExit(snapshot, confirmNormalLeave: true);
    } finally {
      _isGroupExitInFlight = false;
    }
  }

  Future<void> _dispatchFreshGroupExit(
    GroupExitSnapshot snapshot, {
    required bool confirmNormalLeave,
  }) async {
    final group = snapshot.group;
    if (group == null) {
      return;
    }
    switch (snapshot.disposition) {
      case GroupExitDisposition.noOp:
        _markGroupChanged(group.id);
        await _refreshOrbitGroup(group.id);
        return;
      case GroupExitDisposition.deleteDissolvedLocally:
        await _confirmDeleteDissolvedGroup(group.id);
        return;
      case GroupExitDisposition.selfRemovedDeleteLocally:
        await _confirmDeleteSelfRemovedGroupShell(group.id);
        return;
      case GroupExitDisposition.soleAdminRecovery:
        await _showGroupExitRecovery(snapshot);
        return;
      case GroupExitDisposition.pendingRoleSync:
        await _runActiveGroupExit(group, openRecoveryWhenBlocked: true);
        return;
      case GroupExitDisposition.leave:
        if (confirmNormalLeave) {
          final l10n = AppLocalizations.of(context)!;
          final confirmed = await showConfirmationDialog(
            context: context,
            title: l10n.orbit_leave_group,
            description: l10n.orbit_leave_group_body,
            confirmLabel: l10n.orbit_leave_group_action,
          );
          if (!confirmed || !mounted) return;

          final finalSnapshot = await _resolveFreshGroupExit(group.id);
          if (!mounted || finalSnapshot == null) return;
          if (finalSnapshot.group == null) {
            _markGroupChanged(group.id);
            await _refreshOrbitGroup(group.id);
            return;
          }
          if (finalSnapshot.disposition != GroupExitDisposition.leave) {
            await _dispatchFreshGroupExit(
              finalSnapshot,
              confirmNormalLeave: false,
            );
            return;
          }
        }
        await _runActiveGroupExit(group, openRecoveryWhenBlocked: true);
        return;
    }
  }

  Future<bool> _runActiveGroupExit(
    GroupModel group, {
    required bool openRecoveryWhenBlocked,
  }) async {
    final result = await requestGroupExitIntentLeave(group.id);
    return _handleGroupExitIntentResult(
      group,
      result,
      openRecoveryWhenBlocked: openRecoveryWhenBlocked,
    );
  }

  Future<bool> _handleGroupExitIntentResult(
    GroupModel group,
    GroupExitIntentRequestResult result, {
    required bool openRecoveryWhenBlocked,
  }) async {
    if (!mounted) return false;
    switch (result.status) {
      case GroupExitIntentRequestStatus.started:
      case GroupExitIntentRequestStatus.noOp:
        _openRowNotifier.value = null;
        _markGroupChanged(group.id);
        await _refreshOrbitGroup(group.id);
        return true;
      case GroupExitIntentRequestStatus.pendingRoleSync:
        await _showPendingIntentExit(group, result);
        return false;
      case GroupExitIntentRequestStatus.queued:
        await _showQueuedIntentExit(group, result);
        return false;
      case GroupExitIntentRequestStatus.blockedLastAdmin:
        if (result.intent != null) {
          await _showQueuedIntentExit(group, result);
          return false;
        }
        final refreshed = await _resolveFreshGroupExit(group.id);
        if (openRecoveryWhenBlocked && mounted && refreshed != null) {
          if (refreshed.disposition == GroupExitDisposition.soleAdminRecovery) {
            await _showGroupExitRecovery(refreshed);
          } else if (refreshed.disposition ==
              GroupExitDisposition.pendingRoleSync) {
            await _showPendingIntentExit(group);
          }
        }
        return false;
      case GroupExitIntentRequestStatus.unavailable:
        if (result.intent != null) {
          await _showQueuedIntentExit(group, result);
          return false;
        }
        _markGroupChanged(group.id);
        await _refreshOrbitGroup(group.id);
        if (mounted) {
          _showSnackBar(_presentExitResultFailure(result));
        }
        return false;
      case GroupExitIntentRequestStatus.failed:
        if (result.intent != null) {
          await _showQueuedIntentExit(group, result);
          return false;
        }
        _markGroupChanged(group.id);
        await _refreshOrbitGroup(group.id);
        if (mounted) {
          _showSnackBar(_presentExitResultFailure(result));
        }
        return false;
    }
  }

  Future<bool> _closeSheetForGroupExitResult(
    GroupExitIntentRequestResult result,
  ) async {
    if (!mounted) return false;
    switch (result.status) {
      case GroupExitIntentRequestStatus.started:
      case GroupExitIntentRequestStatus.queued:
      case GroupExitIntentRequestStatus.noOp:
        return true;
      case GroupExitIntentRequestStatus.pendingRoleSync:
        return false;
      case GroupExitIntentRequestStatus.blockedLastAdmin:
        _showSnackBar(lastAdminLeaveBlockedMessage);
        return false;
      case GroupExitIntentRequestStatus.unavailable:
      case GroupExitIntentRequestStatus.failed:
        _showSnackBar(_presentExitResultFailure(result));
        return false;
    }
  }

  String _presentExitResultFailure(GroupExitIntentRequestResult result) {
    final l10n = AppLocalizations.of(context)!;
    final code = primaryGroupExitPublicCode(result.diagnosticFacts);
    return code == null
        ? l10n.group_info_leave_failed
        : presentGroupExitDiagnostic(
            l10n,
            code,
            leading: l10n.group_info_leave_failed,
          );
  }

  Future<void> _showPendingIntentExit(
    GroupModel group, [
    GroupExitIntentRequestResult? initialResult,
  ]) async {
    var currentIntentId = initialResult?.intent?.intentId;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => GroupExitRecoverySheet.pendingRoleSync(
        groupName: group.name,
        diagnosticGroupId: group.id,
        diagnosticIntentId: currentIntentId,
        diagnosticActionRef: () => currentIntentId == null
            ? null
            : (groupId: group.id, intentId: currentIntentId!),
        initialDiagnosticCode: initialResult == null
            ? null
            : primaryGroupExitPublicCode(initialResult.diagnosticFacts),
        onLeaveWhenSyncCompletes: () async {
          final result = await queueGroupExitIntentLeaveWhenSyncCompletes(
            group.id,
          );
          currentIntentId = result.intent?.intentId ?? currentIntentId;
          return _closeSheetForGroupExitResult(result);
        },
        onTryAgain: () async {
          final result = await retryGroupExitIntentLeave(group.id);
          currentIntentId = result.intent?.intentId ?? currentIntentId;
          return _closeSheetForGroupExitResult(result);
        },
      ),
    );
    if (!mounted) return;
    _markGroupChanged(group.id);
    await _refreshOrbitGroup(group.id);
  }

  Future<void> _showQueuedIntentExit(
    GroupModel group,
    GroupExitIntentRequestResult initialResult,
  ) async {
    var currentIntentId = initialResult.intent?.intentId;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => GroupExitRecoverySheet.queuedLeave(
        groupName: group.name,
        diagnosticGroupId: group.id,
        diagnosticIntentId: currentIntentId,
        diagnosticActionRef: () => currentIntentId == null
            ? null
            : (groupId: group.id, intentId: currentIntentId!),
        initialDiagnosticCode: primaryGroupExitPublicCode(
          initialResult.diagnosticFacts,
        ),
        onTryAgain: () async {
          final result = await retryGroupExitIntentLeave(group.id);
          currentIntentId = result.intent?.intentId ?? currentIntentId;
          return _closeSheetForGroupExitResult(result);
        },
        onCancelQueuedLeave: () async {
          final result = await cancelQueuedGroupExitIntent(group.id);
          return switch (result.status) {
            GroupExitIntentCancelStatus.cancelled ||
            GroupExitIntentCancelStatus.notFound =>
              GroupExitQueuedCancelUiResult.cancelled,
            GroupExitIntentCancelStatus.tooLate =>
              GroupExitQueuedCancelUiResult.tooLate,
            GroupExitIntentCancelStatus.unavailable ||
            GroupExitIntentCancelStatus.failed =>
              GroupExitQueuedCancelUiResult.failed,
          };
        },
        onRefreshQueuedState: () => _refreshOrbitGroup(group.id),
      ),
    );
    if (!mounted) return;
    _markGroupChanged(group.id);
    await _refreshOrbitGroup(group.id);
  }

  Future<void> _showGroupExitRecovery(GroupExitSnapshot snapshot) async {
    final group = snapshot.group;
    if (!mounted || group == null) return;
    var roleSyncPending = snapshot.hasPendingRoleSync;
    String? pendingSourceEventId;
    for (final row in snapshot.pendingRoleBroadcasts) {
      final sourceMessageId = row.sourceMessageId;
      if (sourceMessageId != null) {
        pendingSourceEventId = sourceMessageId;
        break;
      }
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => GroupExitRecoverySheet(
        groupName: group.name,
        candidates: snapshot.eligibleSuccessors,
        pendingRoleSync: snapshot.hasPendingRoleSync,
        onPromote: (candidate) async {
          try {
            final result = await changeGroupMemberRoleAndBroadcast(
              bridge: widget.bridge,
              groupRepo: widget.groupRepository!,
              identityRepo: widget.identityRepo,
              groupId: group.id,
              memberPeerId: candidate.peerId,
              role: MemberRole.admin,
              messageRepo: widget.groupMessageRepository,
              inviteDeliveryAttemptRepo:
                  widget.groupInviteDeliveryAttemptRepository,
              senderDeviceId: widget.p2pService.currentState.peerId,
              sendP2PMessage: (peerId, message) =>
                  widget.p2pService.sendMessage(peerId, message),
            );
            pendingSourceEventId = result.sourceEventId;
            roleSyncPending =
                result.outcome ==
                ChangeGroupMemberRoleAndBroadcastOutcome.pendingSync;
            _markGroupChanged(group.id);
            await _refreshOrbitGroup(group.id);
            return switch (result.outcome) {
              ChangeGroupMemberRoleAndBroadcastOutcome.readyToLeave =>
                GroupExitPromotionUiResult.readyToLeave,
              ChangeGroupMemberRoleAndBroadcastOutcome.pendingSync =>
                GroupExitPromotionUiResult.pendingSync,
              ChangeGroupMemberRoleAndBroadcastOutcome.unchanged =>
                GroupExitPromotionUiResult.failed,
            };
          } catch (_) {
            emitFlowEvent(
              layer: 'FL',
              event: 'ORBIT_FL_GROUP_EXIT_PROMOTION_ERROR',
              details: const {
                'code': 'EX02',
                'phase': 'role_sync',
                'severity': 'failure',
              },
            );
            return GroupExitPromotionUiResult.failed;
          }
        },
        onRetryPendingSync: () async {
          await drainGroupPendingBroadcastsForGroup(group.id);
          final pending = await loadGroupPendingBroadcasts(group.id);
          final exactSource = pendingSourceEventId;
          if (exactSource != null &&
              pending.any(
                (row) =>
                    isPendingGroupMemberRoleBroadcastKind(row.kind) &&
                    row.sourceMessageId == exactSource,
              )) {
            roleSyncPending = true;
            return false;
          }
          final ready = !pending.any(
            (row) => isPendingGroupMemberRoleBroadcastKind(row.kind),
          );
          roleSyncPending = !ready;
          return ready;
        },
        onContinueLeave: () async {
          final result = roleSyncPending
              ? await queueGroupExitIntentLeaveWhenSyncCompletes(group.id)
              : await requestGroupExitIntentLeave(group.id);
          return _closeSheetForGroupExitResult(result);
        },
        onDissolve: () async {
          final committed = await _dissolveGroupFromOrbit(group.id);
          if (committed && mounted) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) unawaited(_confirmDeleteDissolvedGroup(group.id));
            });
          }
          return committed;
        },
      ),
    );
    if (mounted) await _refreshOrbitGroup(group.id);
  }

  Future<bool> _dissolveGroupFromOrbit(String groupId) async {
    final groupRepo = widget.groupRepository;
    final messageRepo = widget.groupMessageRepository;
    if (!mounted || groupRepo == null || messageRepo == null) return false;
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showConfirmationDialog(
      context: context,
      title: l10n.group_info_dissolve_title,
      description: l10n.group_info_dissolve_body,
      confirmLabel: l10n.group_info_dissolve_action,
    );
    if (!confirmed || !mounted) return false;
    DissolveGroupResult? result;
    GroupModel? transitionGroup;
    Object? transitionError;
    try {
      final identity = await widget.identityRepo.loadIdentity();
      if (identity == null) throw StateError(l10n.group_info_no_identity);
      final senderBinding = await resolveGroupSenderDeviceBinding(
        groupRepo: groupRepo,
        groupId: groupId,
        senderPeerId: identity.peerId,
        preferredDeviceId: widget.p2pService.currentState.peerId,
        preferredTransportPeerId: widget.p2pService.currentState.peerId,
        senderPublicKey: identity.publicKey,
      );
      final (dissolveResult, dissolvedGroup) = await dissolveGroup(
        bridge: widget.bridge,
        groupRepo: groupRepo,
        msgRepo: messageRepo,
        preflightAuthority: requireGroupDissolvePreflightAuthority(),
        groupId: groupId,
        actorPeerId: identity.peerId,
        actorUsername: identity.username,
        actorPublicKey: identity.publicKey,
        actorPrivateKey: identity.privateKey,
        actorDeviceId: senderBinding.deviceId,
        actorTransportPeerId: senderBinding.transportPeerId,
        actorKeyPackageId: senderBinding.keyPackageId,
      );
      result = dissolveResult;
      transitionGroup = dissolvedGroup;
    } catch (error) {
      transitionError = error;
      emitFlowEvent(
        layer: 'FL',
        event: 'ORBIT_FL_DISSOLVE_GROUP_ERROR',
        details: {'stage': 'transition', 'error': error.toString()},
      );
    }

    GroupModel? fresh;
    var commitReadSucceeded = false;
    try {
      fresh = await groupRepo.getGroup(groupId);
      commitReadSucceeded = true;
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ORBIT_FL_DISSOLVE_GROUP_ERROR',
        details: {'stage': 'commit_read', 'error': error.toString()},
      );
    }
    // A successful repository read is the current membership authority. The
    // transition return value describes the membership that was dissolved, but
    // a same-id rejoin can already have materialized a new active group before
    // this continuation resumes. Only fall back to the returned transition when
    // the authoritative read itself was unavailable.
    final committed = commitReadSucceeded
        ? fresh?.isDissolved == true
        : transitionGroup?.isDissolved == true;
    if (!committed && transitionError != null) {
      if (mounted) _showSnackBar(l10n.group_info_dissolve_failed);
      return false;
    }
    Object? pendingCleanupError;
    if (committed) {
      try {
        await discardGroupPendingBroadcasts(groupId);
      } catch (error) {
        pendingCleanupError = error;
        emitFlowEvent(
          layer: 'FL',
          event: 'ORBIT_FL_DISSOLVE_GROUP_ERROR',
          details: {'stage': 'pending_cleanup', 'error': error.toString()},
        );
      }
    }
    _markGroupChanged(groupId);
    try {
      await _refreshOrbitGroup(groupId);
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ORBIT_FL_DISSOLVE_GROUP_ERROR',
        details: {'stage': 'refresh', 'error': error.toString()},
      );
    }
    if (!mounted) return committed;
    final message = pendingCleanupError != null || transitionError != null
        ? l10n.group_info_dissolved_recovery
        : switch (result) {
            DissolveGroupResult.success =>
              committed
                  ? l10n.group_dissolved
                  : l10n.group_info_dissolve_failed,
            DissolveGroupResult.bridgeError =>
              committed
                  ? l10n.group_info_dissolved_recovery
                  : l10n.group_info_dissolve_failed,
            DissolveGroupResult.alreadyDissolved =>
              committed
                  ? l10n.group_info_already_dissolved
                  : l10n.group_info_dissolve_failed,
            DissolveGroupResult.unauthorized =>
              l10n.group_info_admins_only_dissolve,
            DissolveGroupResult.notFound => l10n.group_info_not_found,
            DissolveGroupResult.exitWorkPending =>
              l10n.group_info_dissolve_failed,
            null => l10n.group_info_dissolve_failed,
          };
    _showSnackBar(message);
    return committed;
  }

  Future<void> _confirmDeleteDissolvedGroup(String groupId) async {
    final groupRepository = widget.groupRepository;
    final groupMessageRepository = widget.groupMessageRepository;
    if (!mounted || groupRepository == null || groupMessageRepository == null) {
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showConfirmationDialog(
      context: context,
      title: l10n.group_info_delete_local_title,
      description: l10n.group_info_delete_local_body,
      confirmLabel: l10n.group_info_delete_local_action,
    );
    if (!confirmed || !mounted) return;
    try {
      final observation = await runDeleteDissolvedGroupShellPresentationAction(
        groupId: groupId,
        legacyTestCallback: (groupId) => deleteGroupAndMessages(
          groupRepo: groupRepository,
          groupMessageRepo: groupMessageRepository,
          groupId: groupId,
        ),
      );
      if (observation.status ==
          DeleteDissolvedGroupShellActionStatus.authorityUnavailable) {
        if (mounted) {
          _showSnackBar(
            presentGroupExitDiagnostic(
              l10n,
              observation.publicCode ?? GroupExitDiagnosticPublicCode.ex01,
              leading: l10n.group_info_delete_local_failed,
            ),
          );
        }
        return;
      }
      _openRowNotifier.value = null;
      _markGroupChanged(groupId);
      await _refreshOrbitGroup(groupId);
    } on DissolvedGroupDeleteStateChangedException {
      if (mounted) _showSnackBar(l10n.group_info_delete_local_failed);
    } catch (_) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ORBIT_FL_DELETE_GROUP_ERROR',
        details: const {
          'code': 'EX10',
          'phase': 'local_delete',
          'severity': 'failure',
        },
      );
      if (mounted) {
        _showSnackBar(
          presentGroupExitDiagnostic(
            l10n,
            GroupExitDiagnosticPublicCode.ex10,
            leading: l10n.group_info_delete_local_failed,
          ),
        );
      }
    }
  }

  Future<void> _confirmDeleteSelfRemovedGroupShell(String groupId) async {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showConfirmationDialog(
      context: context,
      title: l10n.group_removed_delete_title,
      description: l10n.group_removed_delete_body,
      confirmLabel: l10n.group_removed_delete_action,
    );
    if (!confirmed || !mounted) return;

    DeleteSelfRemovedGroupShellActionObservation observation;
    try {
      observation = await runDeleteSelfRemovedGroupShellPresentationAction(
        groupId: groupId,
        identityRepository: widget.identityRepo,
        legacyTestCallback: widget.deleteSelfRemovedGroupShell,
      );
    } catch (_) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ORBIT_FL_DELETE_SELF_REMOVED_GROUP_ERROR',
        details: const {
          'code': 'EX10',
          'phase': 'local_delete',
          'severity': 'failure',
        },
      );
      observation = const DeleteSelfRemovedGroupShellActionObservation(
        result: DeleteSelfRemovedGroupShellResult.cleanupIncomplete,
        publicCode: GroupExitDiagnosticPublicCode.ex10,
      );
    }
    if (!mounted) return;

    _markGroupChanged(groupId);
    switch (observation.result) {
      case DeleteSelfRemovedGroupShellResult.deleted:
      case DeleteSelfRemovedGroupShellResult.alreadyAbsent:
        _openRowNotifier.value = null;
        await _refreshOrbitGroup(groupId);
        return;
      case DeleteSelfRemovedGroupShellResult.refusedStateChanged:
        await _refreshOrbitGroup(groupId);
        return;
      case DeleteSelfRemovedGroupShellResult.cleanupIncomplete:
        await _refreshOrbitGroup(groupId);
        if (mounted) {
          _showSnackBar(
            observation.publicCode == null
                ? l10n.group_removed_delete_failed
                : presentGroupExitDiagnostic(
                    l10n,
                    observation.publicCode!,
                    leading: l10n.group_removed_delete_failed,
                  ),
          );
        }
        return;
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
    );
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
        canRejoinForExitIntent: canRejoinForExitIntent,
        processExitIntent: processExistingGroupExitIntent,
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
    GroupExitSnapshot? snapshot;
    try {
      snapshot = await _resolveFreshGroupExit(group.group.id);
    } catch (_) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ORBIT_FL_STUCK_EXIT_CLASSIFY_ERROR',
        details: const {
          'code': 'EX01',
          'phase': 'authority',
          'severity': 'failure',
        },
      );
    }
    if (!mounted) return;
    if (snapshot == null) {
      final l10n = AppLocalizations.of(context)!;
      _showSnackBar(
        group.group.selfRemovedAt != null
            ? l10n.group_removed_delete_failed
            : l10n.group_info_leave_failed,
      );
      return;
    } else if (snapshot.group == null) {
      _markGroupChanged(group.group.id);
      await _refreshOrbitGroup(group.group.id);
      return;
    } else if (snapshot.disposition ==
        GroupExitDisposition.selfRemovedDeleteLocally) {
      await _confirmDeleteSelfRemovedGroupShell(group.group.id);
      return;
    } else if (snapshot.disposition == GroupExitDisposition.noOp) {
      _markGroupChanged(group.group.id);
      await _refreshOrbitGroup(group.group.id);
      return;
    }
    await _dispatchFreshGroupExit(snapshot, confirmNormalLeave: false);
    _markGroupChanged(group.group.id);
    await _refreshOrbitGroup(group.group.id);
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
              groupMediaDownloadCoordinator:
                  widget.groupMediaDownloadCoordinator,
              openAnnouncementSenderConversation: _openConversationForContact,
              inviteDeliveryAttemptRepo:
                  widget.groupInviteDeliveryAttemptRepository,
              bridge: widget.bridge,
              identityRepo: widget.identityRepo,
              contactRepo: widget.contactRepo,
              p2pService: widget.p2pService,
              mediaAttachmentRepo: widget.mediaAttachmentRepo,
              mediaDeleteForMeCoordinator:
                  widget.groupMediaDeleteForMeCoordinator,
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
              forwardMessageRepository: widget.messageRepo,
              forwardChatMessageListener: widget.chatMessageListener,
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
              groupMediaDownloadCoordinator:
                  widget.groupMediaDownloadCoordinator,
              openAnnouncementSenderConversation: _openConversationForContact,
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

class _OrbitInviteRequestTarget {
  final String peerId;
  final String groupName;

  const _OrbitInviteRequestTarget({
    required this.peerId,
    required this.groupName,
  });
}
