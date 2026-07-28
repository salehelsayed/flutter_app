import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/core/device/upload_wake_lock.dart';
import 'package:flutter_app/core/media/app_owned_media_path_authority.dart';
import 'package:flutter_app/core/media/audio_recorder_service.dart';
import 'package:flutter_app/core/media/direct_private_media_path_guard.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/group_media_mime_policy.dart';
import 'package:flutter_app/core/media/group_media_size_policy.dart';
import 'package:flutter_app/core/permissions/mic_permission_gateway.dart';
import 'package:flutter_app/core/permissions/mic_permission_prompt.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_picker.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/media_storage_manager.dart';
import 'package:flutter_app/core/media/media_upload_in_flight_tracker.dart';
import 'package:flutter_app/core/media/private_media_protection_coordinator.dart';
import 'package:flutter_app/core/media/pending_composer_media.dart';
import 'package:flutter_app/core/media/picture_in_picture_gateway.dart';
import 'package:flutter_app/core/media/received_media_egress.dart';
import 'package:flutter_app/core/media/received_media_egress_service.dart';
import 'package:flutter_app/core/media/upload_retry_projection.dart';
import 'package:flutter_app/core/widgets/quiet_confirm.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/services/share_intent_model.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/utils/notification_tap_timing.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/download_media_use_case.dart';
import 'package:flutter_app/features/conversation/application/media_viewer_repository_resume_store.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/media_rejection.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/compose_area.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/groups/application/group_media_delete_for_me_coordinator.dart';
import 'package:flutter_app/features/groups/application/foreground_group_media_upload.dart';
import 'package:flutter_app/features/groups/application/announcement_private_reply_policy.dart';
import 'package:flutter_app/features/groups/application/announcement_private_reply_request.dart';
import 'package:flutter_app/features/groups/application/announcement_media_forward_request.dart';
import 'package:flutter_app/features/groups/application/group_media_batch_forward.dart';
import 'package:flutter_app/features/groups/application/group_media_forward_intent.dart';
import 'package:flutter_app/features/groups/application/group_media_forward_policy.dart';
import 'package:flutter_app/features/groups/application/group_exit_intent_sink.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/group_private_media_availability.dart';
import 'package:flutter_app/features/groups/application/group_private_media_lifecycle.dart';
import 'package:flutter_app/features/groups/application/group_private_media_viewer_controller.dart';
import 'package:flutter_app/features/share/presentation/navigation/share_target_picker_route.dart';
import 'package:flutter_app/features/share/application/group_media_batch_forward_delivery_coordinator.dart';
import 'package:flutter_app/features/share/application/share_batch_delivery_coordinator.dart';
import 'package:flutter_app/features/share/presentation/navigation/group_media_batch_forward_picker_route.dart';
import 'package:flutter_app/features/groups/application/group_media_allowed_peers.dart';
import 'package:flutter_app/features/groups/application/group_received_media_action_policy.dart';
import 'package:flutter_app/features/groups/application/group_received_media_actions.dart';
import 'package:flutter_app/features/groups/application/group_shared_media_batch_actions.dart';
import 'package:flutter_app/features/groups/application/group_shared_media_library_controller.dart';
import 'package:flutter_app/features/groups/application/group_shared_media_navigation.dart';
import 'package:flutter_app/features/groups/application/group_recovery_gate.dart';
import 'package:flutter_app/features/groups/application/group_sender_display_name.dart';
import 'package:flutter_app/features/conversation/application/load_reactions_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_change.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/groups/application/remove_group_reaction_use_case.dart';
import 'package:flutter_app/features/groups/application/retry_failed_group_messages_use_case.dart';
import 'package:flutter_app/features/groups/application/retry_incomplete_group_downloads_use_case.dart';
import 'package:flutter_app/features/groups/application/retry_incomplete_group_uploads_use_case.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/application/send_group_reaction_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_exit_intent.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/application/group_member_device_safety.dart';
import 'package:flutter_app/features/groups/domain/models/group_member_identity_safety.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_private_media_policy.dart';
import 'package:flutter_app/features/groups/domain/models/group_history_gap_repair.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_history_gap_repair_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_reaction_replay_outbox_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/conversation/domain/utils/message_window_cap.dart';
import 'package:flutter_app/features/groups/domain/utils/group_message_ordering.dart';
import 'package:flutter_app/features/groups/presentation/group_backlog_retention_notice.dart';
import 'package:flutter_app/features/groups/presentation/group_security_status_view_state.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_screen.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_info_wired.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_private_media_viewer.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_shared_media_library_screen.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_media_info_sheet.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_reaction_details_sheet.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/settings/application/media_download_policy.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_app/features/settings/domain/models/image_quality_preference.dart';
import 'package:flutter_app/features/settings/domain/models/media_download_preferences.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/conversation/conversation_composer_controller.dart';
import 'package:flutter_app/shared/widgets/conversation/conversation_reaction_projection_controller.dart';
import 'package:flutter_app/shared/widgets/conversation/conversation_upload_activity_controller.dart';
import 'package:flutter_app/shared/widgets/conversation/conversation_voice_capture_controller.dart';
import 'package:flutter_app/shared/widgets/media/full_screen_typed_media_viewer.dart';
import 'package:flutter_app/shared/widgets/media/media_picture_in_picture_controller.dart';
import 'package:flutter_app/shared/widgets/media/media_viewer_item.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class _PreparedGroupMediaUpload {
  final PendingComposerMedia source;
  final MediaAttachment pendingAttachment;
  final String absoluteDurablePath;

  const _PreparedGroupMediaUpload({
    required this.source,
    required this.pendingAttachment,
    required this.absoluteDurablePath,
  });
}

class _RejectedPendingGroupMediaException implements Exception {
  const _RejectedPendingGroupMediaException();
}

class _RestoredGroupMediaContinuation {
  final String groupId;
  final String messageId;
  final DateTime timestamp;
  final String draftText;
  final String? quotedMessageId;
  final String attachmentFingerprint;

  const _RestoredGroupMediaContinuation({
    required this.groupId,
    required this.messageId,
    required this.timestamp,
    required this.draftText,
    required this.quotedMessageId,
    required this.attachmentFingerprint,
  });
}

class _RestoredGroupVoiceContinuation {
  final String groupId;
  final String messageId;
  final DateTime timestamp;
  final String? quotedMessageId;

  const _RestoredGroupVoiceContinuation({
    required this.groupId,
    required this.messageId,
    required this.timestamp,
    required this.quotedMessageId,
  });
}

/// Wired widget connecting GroupConversationScreen to business logic.
/// App-owner-only navigation seam. The freshly resolved contact is the sole
/// value allowed to cross from an announcement into the existing 1:1 route.
typedef OpenAnnouncementSenderConversation =
    Future<void> Function(ContactModel contact);

Stream<void> _mergeGroupPictureInPictureAuthorizationStreams(
  Iterable<Stream<void>> streams,
) => Stream<void>.multi((controller) {
  final subscriptions = streams
      .map(
        (stream) => stream.listen(
          (_) => controller.addSync(null),
          onError: controller.addErrorSync,
        ),
      )
      .toList(growable: false);
  controller.onCancel = () async {
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
  };
});

bool _groupAttachmentChangeMatchesCurrent({
  required MediaAttachmentAuthorizationChange change,
  required String groupId,
  required MediaViewerItem? Function()? currentItem,
}) {
  if (change.owner != MediaOwnerLane.group) return false;
  if (change.scopeId != null && change.scopeId != groupId) return false;
  final current = currentItem?.call();
  if (current == null) return true;
  if (current.owner != MediaOwnerLane.group) return false;
  if (change.messageId != null && change.messageId != current.messageId) {
    return false;
  }
  if (change.attachmentId != null &&
      change.attachmentId != current.attachmentId) {
    return false;
  }
  return true;
}

/// Exact-current view of group listener, local repository, and attachment
/// mutations. Remote tombstones stay group-scoped because their system row id
/// differs from the parent they durably removed.
Stream<void> groupPictureInPictureAuthorizationChanges(
  Stream<GroupMessage> messageChanges, {
  required String groupId,
  Stream<GroupMessageAuthorizationChange> repositoryChanges =
      const Stream<GroupMessageAuthorizationChange>.empty(),
  Stream<MediaAttachmentAuthorizationChange> attachmentChanges =
      const Stream<MediaAttachmentAuthorizationChange>.empty(),
  MediaViewerItem? Function()? currentItem,
}) => _mergeGroupPictureInPictureAuthorizationStreams([
  messageChanges
      .where((message) => message.groupId == groupId)
      .map<void>((_) {}),
  repositoryChanges
      .where((change) {
        if (change.groupId != groupId) return false;
        final current = currentItem?.call();
        return current == null ||
            (current.owner == MediaOwnerLane.group &&
                (change.messageId == null ||
                    change.messageId == current.messageId));
      })
      .map<void>((_) {}),
  attachmentChanges
      .where(
        (change) => _groupAttachmentChangeMatchesCurrent(
          change: change,
          groupId: groupId,
          currentItem: currentItem,
        ),
      )
      .map<void>((_) {}),
]);

/// Immutable dependencies and sender identity for one group send attempt.
///
/// A [GroupConversationWired] State can be retained while its widget is
/// retargeted from group A to group B. Async upload/voice work must therefore
/// finish (or abort) against the exact A dependencies it started with instead
/// of dereferencing the later B widget after an `await`.
final class _GroupConversationSendLane {
  const _GroupConversationSendLane({
    required this.groupId,
    required this.bindingGeneration,
    required this.groupRepository,
    required this.messageRepository,
    required this.inviteDeliveryAttemptRepository,
    required this.bridge,
    required this.p2pService,
    required this.mediaAttachmentRepository,
    required this.mediaFileManager,
    required this.uploadMedia,
    required this.uploadRetryProjectionRepository,
    required this.privateMediaAvailability,
    required this.senderPeerId,
    required this.senderUsername,
    required this.senderPublicKey,
    required this.senderPrivateKey,
    required this.senderDeviceId,
  });

  final String groupId;
  final int bindingGeneration;
  final GroupRepository groupRepository;
  final GroupMessageRepository messageRepository;
  final GroupInviteDeliveryAttemptRepository? inviteDeliveryAttemptRepository;
  final Bridge bridge;
  final P2PService p2pService;
  final MediaAttachmentRepository? mediaAttachmentRepository;
  final MediaFileManager? mediaFileManager;
  final UploadMediaFn uploadMedia;
  final GroupUploadRetryProjectionRepository? uploadRetryProjectionRepository;
  final GroupPrivateMediaAvailability privateMediaAvailability;
  final String senderPeerId;
  final String senderUsername;
  final String senderPublicKey;
  final String senderPrivateKey;
  final String? senderDeviceId;
}

class GroupConversationWired extends StatefulWidget {
  /// 204 (BUG-1): the explicit Cancel row on the attach-source bottom sheet.
  /// Distinct from the 1:1 key so surface-specific tests target each
  /// unambiguously (the two sheets are duplicated per surface).
  static const attachSheetCancelKey = ValueKey('group-attach-cancel-action');

  /// 159 (TC-159-05): a test-only counter incremented once per actual group
  /// display-items recompute on the wired State (the group memo is hoisted here
  /// because [GroupConversationScreen] is a StatelessWidget). Tests reset it.
  @visibleForTesting
  static int debugGroupDisplayItemsBuildCount = 0;

  /// 159 (TC-159-08): a test-only counter incremented once per group
  /// upsert/reorder. A live-stream burst of M events runs M synchronous reorders
  /// on HEAD; the per-frame coalescer collapses the burst into ONE reorder.
  @visibleForTesting
  static int debugReorderInvocationCount = 0;

  final GroupModel group;
  final GroupRepository groupRepo;
  final GroupMessageRepository msgRepo;
  final GroupMessageListener groupMessageListener;
  final GroupInviteDeliveryAttemptRepository? inviteDeliveryAttemptRepo;
  final Bridge bridge;
  final IdentityRepository identityRepo;
  final ContactRepository contactRepo;
  final P2PService p2pService;
  final MediaAttachmentRepository? mediaAttachmentRepo;
  final MediaFileManager? mediaFileManager;
  final ImageProcessor? imageProcessor;
  final MediaPicker? mediaPicker;
  final ImageQualityPreference qualityPreference;
  final ImageQualityPreference videoQualityPreference;
  final AudioRecorderService? audioRecorderService;

  /// Permission authority for the voice-record mic (152) — shared seam with the
  /// 1:1 screen. On denial the screen routes through this gateway so a
  /// `permanentlyDenied` user sees the shared rationale dialog + "Open Settings"
  /// deep-link instead of a dead-end toast. Production gets the real plugin via
  /// the default; tests inject a fake.
  final MicPermissionGateway micPermissionGateway;
  final ActiveConversationTracker? groupConversationTracker;
  final String? initialHighlightedMessageId;
  final List<File>? initialAttachments;
  final List<PendingComposerMedia>? initialPendingMedia;
  final String? initialText;
  final ReactionRepository? reactionRepo;
  final GroupReactionReplayOutboxRepository?
  groupReactionReplayOutboxRepository;
  final GroupHistoryGapRepairRepository? historyGapRepairRepo;
  final UploadMediaFn uploadMediaFn;
  final GroupUploadRetryProjectionRepository? uploadRetryProjectionRepo;
  final GroupPrivateMediaAvailability privateMediaAvailability;
  final int maxAttachmentBudgetBytes;
  final DateTime? notificationTappedAt;
  final BackgroundPreference backgroundPreference;

  /// 247: complete app-owner route to an existing direct conversation. Null
  /// means this construction path cannot safely offer Message sender.
  final OpenAnnouncementSenderConversation? openAnnouncementSenderConversation;

  /// 229: user auto-download policy consulted immediately before every
  /// automatic group media transfer (initial load and live-stream recovery).
  /// The product kind is derived from [group]: announcement groups decide on
  /// the announcement lane, every other group type on the discussion lane;
  /// storage stays [MediaOwnerLane.group] for both. Null preserves HEAD
  /// behavior (allowed). The explicit unavailable-media retry is
  /// user-authoritative and never gated by this decider.
  final MediaAutoDownloadDecider? autoDownloadDecider;

  /// 269: the one app-owned coordinator shared by automatic listener, route,
  /// resume, and periodic group-media recovery triggers. When present, both
  /// initial-load and live-message recovery delegate exact eligible attachment
  /// IDs to it; the explicit user retry remains on this screen's direct path.
  /// Null preserves the legacy route-local recovery for lightweight callers.
  final GroupMediaDownloadCoordinator? groupMediaDownloadCoordinator;

  /// Exact-profile device-proof labels for the real group media renderers.
  /// The map is empty for every ordinary route; the TC-269 post-settlement
  /// route alone binds opaque attachment IDs to safe, non-secret labels.
  final Map<String, String> mediaRenderedSemanticsLabels;

  /// 235: Save/Share qualification adapter. Null (production default when a
  /// media repository is available) constructs the real controller over
  /// [ReceivedMediaEgressService]; tests inject a recording controller. The
  /// UI never calls the native egress gateway or a delivery seam directly.
  final GroupReceivedMediaActionsController? mediaActionsController;

  /// 235: whole-message local delete seam. Production wiring stays null until
  /// the plan-235 persistence slice (DB v98 deletion journal) lands; while
  /// null the Delete-for-me action is not offered.
  final GroupMediaDeleteForMeCoordinator? mediaDeleteForMeCoordinator;

  /// 236: bounded launcher for one ACCEPTED received-media Forward. Tests
  /// inject a recorder; production leaves it null and falls back to pushing
  /// the share target picker in forward mode via
  /// [forwardMessageRepository]/[forwardChatMessageListener].
  final Future<void> Function(
    BuildContext context,
    GroupMediaForwardRequest request,
  )?
  groupMediaForwardLauncher;

  /// 236: 1:1-lane repositories needed only by the forward share-picker
  /// route (contact destinations send through the direct message lane).
  /// Forward is not offered when neither an injected launcher nor these
  /// fallback dependencies are available.
  final MessageRepository? forwardMessageRepository;
  final ChatMessageListener? forwardChatMessageListener;

  const GroupConversationWired({
    super.key,
    required this.group,
    required this.groupRepo,
    required this.msgRepo,
    required this.groupMessageListener,
    this.inviteDeliveryAttemptRepo,
    required this.bridge,
    required this.identityRepo,
    required this.contactRepo,
    required this.p2pService,
    this.mediaAttachmentRepo,
    this.mediaFileManager,
    this.imageProcessor,
    this.mediaPicker,
    this.qualityPreference = ImageQualityPreference.compressed,
    this.videoQualityPreference = ImageQualityPreference.compressed,
    this.audioRecorderService,
    this.micPermissionGateway = const PermissionHandlerMicGateway(),
    this.groupConversationTracker,
    this.initialHighlightedMessageId,
    this.initialAttachments,
    this.initialPendingMedia,
    this.initialText,
    this.reactionRepo,
    this.groupReactionReplayOutboxRepository,
    this.historyGapRepairRepo,
    this.uploadMediaFn = uploadMedia,
    this.uploadRetryProjectionRepo,
    this.privateMediaAvailability = productionGroupPrivateMediaAvailability,
    this.maxAttachmentBudgetBytes = kGeneralMediaAttachmentBudgetBytes,
    this.notificationTappedAt,
    this.backgroundPreference = BackgroundPreference.defaultBackground,
    this.openAnnouncementSenderConversation,
    this.autoDownloadDecider,
    this.groupMediaDownloadCoordinator,
    this.mediaRenderedSemanticsLabels = const <String, String>{},
    this.mediaActionsController,
    this.mediaDeleteForMeCoordinator,
    this.groupMediaForwardLauncher,
    this.forwardMessageRepository,
    this.forwardChatMessageListener,
  });

  @override
  State<GroupConversationWired> createState() => _GroupConversationWiredState();
}

/// 144: a terminal send/reaction result (group dissolved / removed from group /
/// group gone) latches the composer read-only and drives both the banner copy
/// and the per-message "Couldn't send — …" reason. Derived from the use case's
/// LOCAL group reads, so it can flip even when the cached group row still looks
/// writable (e.g. empty-membership dissolved, or a lost-membership the row has
/// not caught up to yet). Reset is intentionally absent: a terminal group state
/// does not self-heal within an open screen.
enum _TerminalReadOnly { none, dissolved, removed, unavailable }

class _GroupConversationWiredState extends State<GroupConversationWired>
    with WidgetsBindingObserver {
  static const _maxAttachments = 10;
  static const _liveEdgeTolerance = 32.0;
  static const _messageLoadErrorCopy = "Couldn't load messages";
  static final MediaPicker _defaultMediaPicker = SystemMediaPicker();

  late GroupModel _group;
  List<GroupMessage> _messages = [];
  AnnouncementPrivateReplyResolver? _announcementPrivateReplyResolver;
  bool _announcementPrivateReplyDispatchInFlight = false;
  final Map<String, AnnouncementPrivateReplyRequest>
  _viewerPrivateReplyRequests = <String, AnnouncementPrivateReplyRequest>{};

  // 159 (main-isolate-blocking-1): the group run-grouping memo, hoisted to the
  // wired State because GroupConversationScreen is a StatelessWidget. Keyed on
  // `_messages` reference identity (every mutation reallocates the list) PLUS the
  // locale + today-token that drive the day-separator labels. Recomputed only
  // when one of those changes; passed to the screen as precomputedDisplayItems.
  List<GroupDisplayItem>? _cachedGroupDisplayItems;
  List<GroupMessage>? _cachedGroupMessagesRef;
  String? _cachedGroupLocale;
  String? _cachedGroupTodayToken;

  // 159 (rebuild-storms-2): per-frame coalescer for the group stream's
  // message-apply setState. A live burst of M events enqueues M updates and
  // applies them in ONE batched setState + ONE reorder on the next frame. The
  // scroll-offset capture/restore + markAsRead side effects run once-per-flush
  // (one capture before / one restore after), never per queued event.
  bool _groupFlushScheduled = false;
  bool _groupNeedsFlush = false;
  bool _groupWantsMarkRead = false;
  int _messageLoadGeneration = 0;
  int _messageLoadsInFlight = 0;
  final Set<int> _activeMessageLoadGenerations = <int>{};
  final Set<String> _insertedIdsDuringMessageLoad = <String>{};
  int _messageMutationGeneration = 0;
  final Map<String, int> _messageMutationGenerations = <String, int>{};
  final Set<String> _locallyRemovedMessageIds = <String>{};

  Map<String, GroupMember> _membersByPeerId = const {};
  String? _ownPeerId;
  String _senderUsername = '';
  String _senderPublicKey = '';
  String _senderPrivateKey = '';
  StreamSubscription<GroupMessage>? _messageSubscription;
  StreamSubscription<GroupOutgoingLocalMessageChange>?
  _outgoingLocalMessageChangeSubscription;
  StreamSubscription<String>? _removedSubscription;
  final ScrollController _scrollController = ScrollController();

  /// Attached to the highlighted row (via the screen) so a notification-tapped
  /// message can be scrolled into view. Resolved once per open.
  final GlobalKey _highlightAnchorKey = GlobalKey();
  static const int _maxHighlightScrollRetries = 5;
  bool _highlightScrollResolved = false;
  String? _highlightedMessageId;
  final GroupSharedMediaAnchorRequestCoordinator _sharedMediaAnchorRequests =
      GroupSharedMediaAnchorRequestCoordinator();
  String? _activeSharedMediaAnchorGroupId;
  String? _activeSharedMediaAnchorTargetId;
  Set<String> _activeSharedMediaAnchorInjectedIds = const <String>{};
  String? _sharedMediaAnchorReplayGroupId;
  String? _sharedMediaAnchorReplayTargetId;
  List<GroupMessage> _sharedMediaAnchorReplayWindow = const <GroupMessage>[];
  Map<String, List<MediaAttachment>> _sharedMediaAnchorReplayMedia =
      const <String, List<MediaAttachment>>{};
  Set<int> _sharedMediaAnchorReplayLoadGenerations = const <int>{};
  bool _initialLoadDone = false;
  bool _isSending = false;
  Set<String> _retryingFailedMessageIds = const {};
  String? _activeQuoteMessageId;
  String _draftText = '';
  String? _messageLoadErrorText;
  GroupSecurityStatusViewState? _securityStatus;
  GroupHistoryGapRepair? _historyGapRepair;
  bool _isCurrentUserActiveMember = true;
  bool _hasCurrentSendKey = true;
  bool _isLifecycleResumed = true;
  _TerminalReadOnly _terminalSendReadOnly = _TerminalReadOnly.none;
  GroupExitIntentLookupStatus? _exitIntentLookupStatus;
  GroupExitIntent? _groupExitIntent;
  // 144 finding: distinguishes "membership never loaded yet" (startup window —
  // do NOT infer removal) from "loaded and genuinely empty/excluding self".
  // Gates the reopen reconstruction of the terminal read-only latch.
  bool _securityStatusLoaded = false;

  // Media state
  late final ConversationComposerController _composerController;
  Map<String, List<MediaAttachment>> _mediaMap = {};
  bool _lastUploadProjectionTerminal = false;

  // 235: received-media action seams. The controller requalifies the reloaded
  // row before every egress call; the delete coordinator is UI-injected only
  // until the v98 journal persistence slice lands.
  GroupReceivedMediaActionsController? _mediaActionsController;
  GroupPrivateMediaViewerController? _lazyPrivateMediaViewerController;
  MediaViewerRepositoryResumeStore? _lazyMediaViewerResumeStore;
  final Set<GroupPrivateMediaViewerIdentity> _privateMediaOpenInFlight = {};

  MediaViewerRepositoryResumeStore? get _mediaViewerResumeStore {
    final existing = _lazyMediaViewerResumeStore;
    if (existing != null) return existing;
    final attachments = widget.mediaAttachmentRepo;
    if (attachments == null || attachments is! MediaLibraryStateRepository) {
      return null;
    }
    return _lazyMediaViewerResumeStore = MediaViewerRepositoryResumeStore(
      attachmentRepository: attachments,
      stateRepository: attachments as MediaLibraryStateRepository,
    );
  }

  MediaPictureInPictureController _createMediaPictureInPictureController({
    required MediaPictureInPictureCurrentAuthorizer reloadCurrent,
    required MediaPictureInPictureRestorePlayback restorePlayback,
  }) {
    final resumeStore = _mediaViewerResumeStore;
    if (resumeStore == null) {
      throw StateError('PiP composition requires media library state');
    }
    final messageRepository = widget.msgRepo;
    final attachmentRepository = widget.mediaAttachmentRepo;
    MediaViewerItem? activeItem;
    Future<MediaPictureInPictureAuthorization?> trackedReloadCurrent() async {
      final authorization = await reloadCurrent();
      if (authorization != null) activeItem = authorization.item;
      return authorization;
    }

    final repositoryChanges =
        messageRepository is GroupMessageAuthorizationChangeSource
        ? (messageRepository as GroupMessageAuthorizationChangeSource)
              .authorizationChanges
        : const Stream<GroupMessageAuthorizationChange>.empty();
    final attachmentChanges =
        attachmentRepository is MediaAttachmentAuthorizationChangeSource
        ? (attachmentRepository as MediaAttachmentAuthorizationChangeSource)
              .authorizationChanges
        : const Stream<MediaAttachmentAuthorizationChange>.empty();
    return MediaPictureInPictureController(
      gateway: PictureInPictureChannelGateway.platform(),
      pathAuthority: IoAppOwnedMediaPathAuthority(),
      reloadCurrent: trackedReloadCurrent,
      resumeStore: resumeStore,
      restorePlayback: restorePlayback,
      authorizationChanges: groupPictureInPictureAuthorizationChanges(
        widget.groupMessageListener.groupMessageStream,
        groupId: widget.group.id,
        repositoryChanges: repositoryChanges,
        attachmentChanges: attachmentChanges,
        currentItem: () => activeItem,
      ),
    );
  }

  /// 235: injected coordinator wins; otherwise the process-wide production
  /// default set by main() (null in tests that set neither -> Delete hidden).
  GroupMediaDeleteForMeCoordinator? _mediaDeleteForMeCoordinator;
  final Set<String> _deleteForMeInFlight = <String>{};

  // Reaction state
  final _reactionProjectionController =
      ConversationReactionProjectionController();
  int _reactionBindingGeneration = 0;
  final Set<String> _retiredReactionMessageIds = <String>{};
  StreamSubscription<ReactionChange>? _reactionSubscription;

  // Voice recording state
  late final ConversationVoiceCaptureController _voiceCaptureController;
  late final ConversationUploadActivityController<ConversationComposerSnapshot>
  _uploadActivityController;
  int _sendLaneBindingGeneration = 0;
  bool _allowPopDuringActiveUpload = false;
  _RestoredGroupMediaContinuation? _restoredMediaContinuation;
  _RestoredGroupVoiceContinuation? _restoredVoiceContinuation;

  MediaPicker get _mediaPicker => widget.mediaPicker ?? _defaultMediaPicker;

  String? get _currentSenderDeviceId {
    final peerId = widget.p2pService.currentState.peerId?.trim();
    return peerId == null || peerId.isEmpty ? null : peerId;
  }

  _GroupConversationSendLane _captureSendLane() {
    final senderPeerId = _ownPeerId;
    if (senderPeerId == null || senderPeerId.isEmpty) {
      throw StateError('Cannot capture a group send lane without a peer ID');
    }
    return _GroupConversationSendLane(
      groupId: widget.group.id,
      bindingGeneration: _sendLaneBindingGeneration,
      groupRepository: widget.groupRepo,
      messageRepository: widget.msgRepo,
      inviteDeliveryAttemptRepository: widget.inviteDeliveryAttemptRepo,
      bridge: widget.bridge,
      p2pService: widget.p2pService,
      mediaAttachmentRepository: widget.mediaAttachmentRepo,
      mediaFileManager: widget.mediaFileManager,
      uploadMedia: widget.uploadMediaFn,
      uploadRetryProjectionRepository: _uploadRetryProjection,
      privateMediaAvailability: widget.privateMediaAvailability,
      senderPeerId: senderPeerId,
      senderUsername: _senderUsername,
      senderPublicKey: _senderPublicKey,
      senderPrivateKey: _senderPrivateKey,
      senderDeviceId: _currentSenderDeviceId,
    );
  }

  bool _canContinueSendLane(_GroupConversationSendLane lane) =>
      lane.bindingGeneration == _sendLaneBindingGeneration &&
      widget.group.id == lane.groupId;

  bool _isCurrentSendLane(_GroupConversationSendLane lane) =>
      mounted && _canContinueSendLane(lane);

  bool _canContinueSendOperation(
    _GroupConversationSendLane lane,
    ConversationUploadOperation<ConversationComposerSnapshot> operation,
  ) {
    if (!_canContinueSendLane(lane)) return false;
    return !mounted || _uploadActivityController.isCurrentOperation(operation);
  }

  bool _isCurrentVoiceSendLane(
    _GroupConversationSendLane lane,
    ConversationVoiceCaptureOutcome outcome,
  ) =>
      _canContinueSendLane(lane) &&
      (!mounted || _voiceCaptureController.isCurrentOutcome(outcome));

  bool _currentLifecycleAllowsVisibleRead() {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  bool get _canMarkVisibleRead {
    if (!_isLifecycleResumed) return false;
    final tracker = widget.groupConversationTracker;
    return tracker == null || tracker.isViewing(_activeGroupConversationKey);
  }

  Future<void> _markVisibleReadIfAllowed() async {
    if (!_canMarkVisibleRead) return;
    await widget.msgRepo.markAsRead(widget.group.id);
  }

  Future<String> _beginBackgroundTaskGuarded({Bridge? bridge}) async {
    try {
      return await callBgBegin(bridge ?? widget.bridge) ?? '';
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_CONV_FL_BG_BEGIN_ERROR',
        details: {'error': e.toString()},
      );
      return '';
    }
  }

  Future<void> _endBackgroundTaskGuarded(
    String bgTaskId, {
    Bridge? bridge,
  }) async {
    if (bgTaskId.isEmpty) return;
    try {
      await callBgEnd(bridge ?? widget.bridge, bgTaskId);
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_CONV_FL_BG_END_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  bool get _isTrackingRelayUpload => _uploadActivityController.isTracking;

  Map<String, String> _activeVisualUploadOwnersByAttachmentId() {
    final result = <String, String>{};
    for (final message in _messages) {
      if (message.isIncoming ||
          (message.status != 'sending' &&
              message.status != GroupMessage.statusQueuedOffline)) {
        continue;
      }
      final attachments = _mediaMap[message.id] ?? message.media;
      for (final attachment in attachments) {
        if (attachment.mediaType == 'image' ||
            attachment.mediaType == 'video' ||
            attachment.mime == 'image/gif') {
          result[attachment.id] = message.id;
        }
      }
    }
    return result;
  }

  bool _hasCompleteSenderIdentityFields({
    required String? peerId,
    required String username,
    required String publicKey,
    required String privateKey,
  }) {
    return peerId?.trim().isNotEmpty == true &&
        username.trim().isNotEmpty &&
        publicKey.trim().isNotEmpty &&
        privateKey.trim().isNotEmpty;
  }

  bool get _hasCompleteSenderIdentity => _hasCompleteSenderIdentityFields(
    peerId: _ownPeerId,
    username: _senderUsername,
    publicKey: _senderPublicKey,
    privateKey: _senderPrivateKey,
  );

  bool _passesGroupMediaAclPreflight(
    Iterable<GroupMember> members, {
    required String surface,
  }) {
    if (groupMediaAllowedPeersForMembers(members).isNotEmpty) {
      return true;
    }
    const failure = UploadMediaFailed(
      stage: UploadMediaStage.validation,
      disposition: UploadMediaDisposition.terminal,
      errorCode: kEmptyGroupMediaAclErrorCode,
    );
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_CONV_FL_MEDIA_ACL_PREFLIGHT_REJECTED',
      details: {
        'surface': surface,
        'stage': failure.stage.name,
        'disposition': failure.disposition.name,
        'errorCode': failure.errorCode,
      },
    );
    return false;
  }

  bool _tryBeginSendFlow() {
    if (_isSending) return false;
    if (mounted) {
      setState(() => _isSending = true);
    } else {
      _isSending = true;
    }
    return true;
  }

  void _endSendFlow() {
    if (!_isSending) return;
    if (mounted) {
      setState(() => _isSending = false);
    } else {
      _isSending = false;
    }
  }

  bool _tryBeginFailedMessageRetry(String messageId) {
    if (_retryingFailedMessageIds.contains(messageId)) return false;
    final next = {..._retryingFailedMessageIds, messageId};
    if (mounted) {
      setState(() => _retryingFailedMessageIds = next);
    } else {
      _retryingFailedMessageIds = next;
    }
    return true;
  }

  void _endFailedMessageRetry(String messageId) {
    if (!_retryingFailedMessageIds.contains(messageId)) return;
    final next = {..._retryingFailedMessageIds}..remove(messageId);
    if (mounted) {
      setState(() => _retryingFailedMessageIds = next);
    } else {
      _retryingFailedMessageIds = next;
    }
  }

  @override
  void initState() {
    super.initState();
    _composerController = ConversationComposerController();
    _uploadActivityController =
        ConversationUploadActivityController<ConversationComposerSnapshot>(
          scopeId: widget.group.id,
          resolveActiveOwners: _activeVisualUploadOwnersByAttachmentId,
          acquireWake: UploadWakeLockController.acquire,
          releaseWake: UploadWakeLockController.release,
        );
    _uploadActivityController.addListener(_onControllerInvalidated);
    _reactionProjectionController.addListener(_onControllerInvalidated);
    _voiceCaptureController = ConversationVoiceCaptureController(
      onAutoStopOutcome: _onVoiceCaptureAutoStopOutcome,
    );
    _voiceCaptureController.addListener(_onVoiceCaptureStateChanged);
    _uploadActivityController.bindProgressStream(mediaUploadProgressStream);
    WidgetsBinding.instance.addObserver(this);
    _group = widget.group;
    _highlightedMessageId = widget.initialHighlightedMessageId;
    final mediaRepo = widget.mediaAttachmentRepo;
    _announcementPrivateReplyResolver = mediaRepo == null
        ? null
        : AnnouncementPrivateReplyResolver(
            identityRepository: widget.identityRepo,
            groupMessageRepository: widget.msgRepo,
            groupRepository: widget.groupRepo,
            mediaAttachmentRepository: mediaRepo,
            contactRepository: widget.contactRepo,
          );
    _mediaActionsController =
        widget.mediaActionsController ??
        (mediaRepo != null
            ? GroupReceivedMediaActionsController(
                messageRepository: widget.msgRepo,
                mediaAttachmentRepository: mediaRepo,
                egressService: ReceivedMediaEgressService(),
                mediaFileManager: widget.mediaFileManager,
              )
            : null);
    _mediaDeleteForMeCoordinator =
        widget.mediaDeleteForMeCoordinator ??
        defaultGroupMediaDeleteForMeCoordinator;
    _isLifecycleResumed = _currentLifecycleAllowsVisibleRead();
    _draftText = widget.initialText ?? '';
    widget.groupConversationTracker?.setActive(_activeGroupConversationKey);
    _updateComposerState(pendingAttachments: const <PendingComposerMedia>[]);
    final initialPendingMedia = widget.initialPendingMedia;
    final initialAttachments = widget.initialAttachments;
    if (initialPendingMedia != null && initialPendingMedia.isNotEmpty) {
      final seeded = _seedInitialPendingMediaIfWithinBudget(
        initialPendingMedia,
      );
      if (!seeded) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(_hydrateInitialPendingMedia(initialPendingMedia));
        });
      }
    } else if (initialAttachments != null && initialAttachments.isNotEmpty) {
      final prepared = _prepareLegacyInitialAttachmentsSync(initialAttachments);
      final seeded = prepared.isNotEmpty
          ? _seedInitialPendingMediaIfWithinBudget(prepared)
          : false;
      if (!seeded) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(_hydrateLegacyInitialAttachments(initialAttachments));
        });
      }
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_CONV_FL_SCREEN_INIT',
      details: {
        'groupId': widget.group.id.length > 8
            ? widget.group.id.substring(0, 8)
            : widget.group.id,
      },
    );
    _loadIdentity();
    unawaited(_refreshExitIntent());
    _loadMessages();
    unawaited(_loadSecurityStatus());
    _startListening();
    _startListeningForOutgoingLocalMessageChanges();
    _startListeningForReactions();
  }

  bool _notificationTimingEmitted = false;

  void _onControllerInvalidated() {
    if (mounted) setState(() {});
  }

  void _onVoiceCaptureStateChanged() {
    if (!mounted) return;
    final voiceState = _voiceCaptureController.state;
    final recordingState = switch (voiceState.phase) {
      ConversationVoiceCapturePhase.idle => VoiceRecordingState.idle,
      ConversationVoiceCapturePhase.arming => VoiceRecordingState.arming,
      ConversationVoiceCapturePhase.recording => VoiceRecordingState.recording,
      ConversationVoiceCapturePhase.stopping => VoiceRecordingState.stopping,
    };
    _updateComposerState(
      recordingState: recordingState,
      recordingDuration: voiceState.duration,
      amplitudeValues: voiceState.amplitudeValues,
    );
  }

  void _emitNotificationTapTimingIfNeeded() {
    final tappedAt = widget.notificationTappedAt;
    if (tappedAt == null || _notificationTimingEmitted) return;
    _notificationTimingEmitted = true;
    emitNotificationTapTiming(
      tappedAt: tappedAt,
      routeKind: 'group',
      messageId: widget.initialHighlightedMessageId,
    );
  }

  Future<ConversationUploadOperation<ConversationComposerSnapshot>>
  _startRelayUploadTracking(
    int totalBytes, {
    ConversationUploadOperation<ConversationComposerSnapshot>? operation,
  }) async {
    final exactOperation =
        operation ??
        _uploadActivityController.activeOperation ??
        _uploadActivityController.beginOperation();
    await _uploadActivityController.startTracking(
      exactOperation,
      totalBytes: totalBytes,
    );
    return exactOperation;
  }

  void _markRelayUploadStarted(
    ConversationUploadOperation<ConversationComposerSnapshot> operation,
    String uploadId,
  ) {
    _uploadActivityController.markUploadStarted(operation, uploadId);
  }

  void _markRelayUploadCompleted(
    ConversationUploadOperation<ConversationComposerSnapshot> operation,
    int sizeBytes,
  ) {
    _uploadActivityController.markUploadCompleted(operation, sizeBytes);
  }

  Future<void> _stopRelayUploadTracking(
    ConversationUploadOperation<ConversationComposerSnapshot>? operation,
  ) async {
    if (operation != null) {
      await _uploadActivityController.complete(operation);
    }
  }

  ConversationUploadOperation<ConversationComposerSnapshot>
  _beginActiveAttachmentUpload({
    required String messageId,
    required ConversationComposerSnapshot composerSnapshot,
  }) {
    return _uploadActivityController.beginOperation(
      messageId: messageId,
      composerSnapshot: composerSnapshot,
      cancelFinalizer: _finalizeGroupAttachmentUploadCancellation,
    );
  }

  Future<void> _clearActiveAttachmentUpload(
    ConversationUploadOperation<ConversationComposerSnapshot>? operation,
  ) async {
    if (operation != null) {
      await _uploadActivityController.complete(operation);
    }
  }

  void _requestCancelActiveAttachmentUpload() {
    _uploadActivityController.requestCancelActive();
  }

  Future<bool> _cancelActiveAttachmentUploadIfRequested(
    ConversationUploadOperation<ConversationComposerSnapshot>? operation,
  ) async {
    final exactOperation =
        operation ?? _uploadActivityController.activeOperation;
    if (exactOperation == null ||
        !_uploadActivityController.cancellationRequestedFor(exactOperation)) {
      return false;
    }
    return _uploadActivityController.finalizeCancellation(exactOperation);
  }

  Future<bool> _finalizeGroupAttachmentUploadCancellation(
    ConversationUploadOperation<ConversationComposerSnapshot> operation,
  ) async {
    final messageId = operation.messageId;
    final composerSnapshot = operation.composerSnapshot;
    if (messageId == null || composerSnapshot == null) return false;
    await widget.mediaAttachmentRepo
        ?.markUploadPendingAttachmentsFailedForMessage(
          messageId,
          owner: MediaOwnerLane.group,
        );
    if (!_uploadActivityController.isCurrentOperation(operation) || !mounted) {
      return true;
    }
    final uploadCancelledText = AppLocalizations.of(context)!.upload_cancelled;
    await _restoreComposerSnapshot(
      composerSnapshot,
      messageId,
      snackText: uploadCancelledText,
      showSnackBar: true,
    );
    return true;
  }

  Future<bool> _confirmLeaveWhileUploadActive() async {
    if (!_isTrackingRelayUpload || !mounted) return true;
    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (context) {
        final l10n = AppLocalizations.of(context)!;
        return AlertDialog(
          title: Text(l10n.upload_leave_title),
          content: Text(l10n.upload_leave_body),
          actions: [
            TextButton(
              key: const ValueKey('upload-leave-stay'),
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.upload_leave_stay),
            ),
            FilledButton(
              key: const ValueKey('upload-leave-confirm'),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.upload_leave_confirm),
            ),
          ],
        );
      },
    );
    return shouldLeave ?? false;
  }

  @override
  void didUpdateWidget(covariant GroupConversationWired oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.group.id != oldWidget.group.id) {
      _resetForGroupChange(oldWidget);
      return;
    }
    if (!identical(widget.msgRepo, oldWidget.msgRepo)) {
      _restartOutgoingLocalMessageChangeSubscription();
    }
    final oldCanWrite = _canWrite;
    final newCanWrite = _canWriteForGroup(widget.group);
    final shouldSyncGroupFromWidget =
        widget.group.id != _group.id ||
        _matchesGroupSnapshot(_group, oldWidget.group) ||
        _isIncomingGroupNewer(widget.group, _group) ||
        oldCanWrite != newCanWrite;
    if (shouldSyncGroupFromWidget) {
      _group = widget.group;
    }
    if (oldCanWrite && !_canWrite) {
      _forceCancelActiveRecording();
      _activeQuoteMessageId = null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isLifecycleResumed = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed) {
      unawaited(_loadMessages());
      unawaited(_refreshVisibleGroup());
      unawaited(_refreshExitIntent());
      // B5: recompute composer write-access on resume so a membership/key
      // change that landed while backgrounded (e.g. a re-add delivering the
      // current group key via the key-update path, which carries no sys row on
      // this device's message stream) makes the composer reappear without
      // requiring the user to leave and re-enter the conversation.
      unawaited(_loadSecurityStatus());
      unawaited(_markVisibleReadIfAllowed());
    }
  }

  void _resetForGroupChange(GroupConversationWired oldWidget) {
    _sendLaneBindingGeneration++;
    _uploadActivityController.detachView();
    _reactionBindingGeneration++;
    unawaited(_voiceCaptureController.invalidateSessionScope());
    widget.groupConversationTracker?.clearIfActive(
      'group:${oldWidget.group.id}',
    );
    widget.groupConversationTracker?.setActive(_activeGroupConversationKey);
    unawaited(_messageSubscription?.cancel());
    unawaited(_outgoingLocalMessageChangeSubscription?.cancel());
    unawaited(_removedSubscription?.cancel());
    unawaited(_reactionSubscription?.cancel());
    _messageSubscription = null;
    _outgoingLocalMessageChangeSubscription = null;
    _removedSubscription = null;
    _reactionSubscription = null;

    _retiredReactionMessageIds.addAll(_messages.map((message) => message.id));
    _group = widget.group;
    _messages = [];
    _mediaMap = {};
    _uploadActivityController.rebind(
      scopeId: widget.group.id,
      resolveActiveOwners: _activeVisualUploadOwnersByAttachmentId,
    );
    _reactionProjectionController.clear();
    _membersByPeerId = const {};
    _historyGapRepair = null;
    _securityStatus = null;
    _messageLoadErrorText = null;
    _activeSharedMediaAnchorGroupId = null;
    _activeSharedMediaAnchorTargetId = null;
    _activeSharedMediaAnchorInjectedIds = const <String>{};
    _invalidateSharedMediaAnchorReplay();
    _messageMutationGeneration = 0;
    _messageMutationGenerations.clear();
    _locallyRemovedMessageIds.clear();
    _highlightedMessageId = widget.initialHighlightedMessageId;
    _highlightScrollResolved = false;
    // 144: a terminal send-failure latch is per-group; scrub it so a different
    // group does not inherit a stale read-only composer/banner/reason. Also
    // re-enter the startup window (clear _securityStatusLoaded) so the reopen
    // hydration short-circuits until the NEW group's membership has loaded —
    // otherwise a _loadMessages/_loadSecurityStatus race on a same-State
    // group-id change could transiently latch a false `removed`.
    _terminalSendReadOnly = _TerminalReadOnly.none;
    _exitIntentLookupStatus = null;
    _groupExitIntent = null;
    _securityStatusLoaded = false;
    _initialLoadDone = false;
    _activeQuoteMessageId = null;
    _draftText = widget.initialText ?? '';
    _clearRestoredMediaContinuationTracking();
    _clearRestoredVoiceContinuationTracking();
    _updateComposerState(
      pendingAttachments: const <PendingComposerMedia>[],
      isUploading: false,
    );
    if (mounted) {
      setState(() {});
    }

    _loadMessages();
    unawaited(_refreshExitIntent());
    unawaited(_loadSecurityStatus());
    _startListening();
    _startListeningForOutgoingLocalMessageChanges();
    _startListeningForReactions();
  }

  Future<void> _hydrateInitialPendingMedia(
    List<PendingComposerMedia> initialPendingMedia,
  ) async {
    final accepted = await _resolvePendingMediaCandidates(
      candidateAttachments: initialPendingMedia,
    );
    if (!mounted || accepted == null || accepted.isEmpty) return;
    _updateComposerState(pendingAttachments: accepted);
  }

  bool _seedInitialPendingMediaIfWithinBudget(
    List<PendingComposerMedia> initialPendingMedia,
  ) {
    if (initialPendingMedia.isEmpty) return false;
    final totalBudgetBytes = totalPendingComposerBudgetBytes(
      initialPendingMedia,
    );
    if (totalBudgetBytes > widget.maxAttachmentBudgetBytes) {
      return false;
    }
    _updateComposerState(pendingAttachments: initialPendingMedia);
    return true;
  }

  List<PendingComposerMedia> _prepareLegacyInitialAttachmentsSync(
    List<File> attachments,
  ) {
    final prepared = <PendingComposerMedia>[];
    for (final attachment in attachments) {
      if (!attachment.existsSync()) continue;
      try {
        prepared.add(
          PendingComposerMedia(
            file: attachment,
            budgetBytes: attachment.lengthSync(),
          ),
        );
      } catch (_) {
        continue;
      }
    }
    return prepared;
  }

  Future<void> _hydrateLegacyInitialAttachments(List<File> attachments) async {
    final prepared = _prepareLegacyInitialAttachmentsSync(attachments);
    if (prepared.isEmpty) {
      for (final attachment in attachments) {
        if (!await attachment.exists()) continue;
        prepared.add(
          PendingComposerMedia(
            file: attachment,
            budgetBytes: await attachment.length(),
          ),
        );
      }
    }
    if (prepared.isEmpty) return;
    await _hydrateInitialPendingMedia(prepared);
  }

  Future<void> _attemptAddPendingMedia(
    List<PendingComposerMedia> candidateAttachments,
  ) async {
    final accepted = await _resolvePendingMediaCandidates(
      candidateAttachments: candidateAttachments,
    );
    if (!mounted || accepted == null || accepted.isEmpty) return;
    _clearRestoredMediaContinuationTracking();
    _updateComposerState(
      pendingAttachments: [
        ..._composerController.pendingAttachments,
        ...accepted,
      ],
    );
  }

  Future<List<PendingComposerMedia>?> _resolvePendingMediaCandidates({
    required List<PendingComposerMedia> candidateAttachments,
  }) async {
    if (candidateAttachments.isEmpty) return const [];

    final combinedBudgetBytes = totalPendingComposerBudgetBytes([
      ..._composerController.pendingAttachments,
      ...candidateAttachments,
    ]);
    if (combinedBudgetBytes <= widget.maxAttachmentBudgetBytes) {
      return candidateAttachments;
    }

    final shouldCompress = await _showAttachmentOverflowDialog(
      totalBudgetBytes: combinedBudgetBytes,
    );
    if (shouldCompress != true) {
      return null;
    }

    final compressedCandidates = <PendingComposerMedia>[];
    for (final candidate in candidateAttachments) {
      compressedCandidates.add(
        await _preparePendingMedia(
          candidate.file.path,
          imageQualityPreference: ImageQualityPreference.compressed,
          videoQualityPreference: ImageQualityPreference.compressed,
        ),
      );
    }

    final compressedBudgetBytes = totalPendingComposerBudgetBytes([
      ..._composerController.pendingAttachments,
      ...compressedCandidates,
    ]);
    if (compressedBudgetBytes > widget.maxAttachmentBudgetBytes) {
      _showAttachmentTooLargeMessage();
      return null;
    }

    return compressedCandidates;
  }

  String _pendingAttachmentFingerprint(List<PendingComposerMedia> attachments) {
    return attachments
        .map(
          (attachment) => [
            attachment.file.path,
            attachment.budgetBytes.toString(),
            attachment.width?.toString() ?? '',
            attachment.height?.toString() ?? '',
            attachment.durationMs?.toString() ?? '',
          ].join('\u001f'),
        )
        .join('\u001e');
  }

  bool _sameOptionalMessageId(String? left, String? right) {
    final normalizedLeft = left == null || left.isEmpty ? null : left;
    final normalizedRight = right == null || right.isEmpty ? null : right;
    return normalizedLeft == normalizedRight;
  }

  bool _matchesRestoredMediaContinuation({
    required _RestoredGroupMediaContinuation continuation,
    required String groupId,
    required String draftText,
    required String? quotedMessageId,
    required List<PendingComposerMedia> pendingAttachments,
  }) {
    return continuation.groupId == groupId &&
        continuation.draftText == draftText &&
        _sameOptionalMessageId(continuation.quotedMessageId, quotedMessageId) &&
        continuation.attachmentFingerprint ==
            _pendingAttachmentFingerprint(pendingAttachments);
  }

  Future<({bool handled, _RestoredGroupMediaContinuation? continuation})>
  _resolveRestoredMediaContinuationForSend({
    required _GroupConversationSendLane lane,
    required String draftText,
    required String? quotedMessageId,
    required List<PendingComposerMedia> pendingAttachments,
  }) async {
    final continuation = _restoredMediaContinuation;
    if (continuation == null) {
      return (handled: false, continuation: null);
    }
    if (!_matchesRestoredMediaContinuation(
      continuation: continuation,
      groupId: lane.groupId,
      draftText: draftText,
      quotedMessageId: quotedMessageId,
      pendingAttachments: pendingAttachments,
    )) {
      _clearRestoredMediaContinuationTracking();
      return (handled: false, continuation: null);
    }

    final message = await lane.messageRepository.getMessage(
      continuation.messageId,
    );
    if (!_isCurrentSendLane(lane)) {
      return (handled: true, continuation: null);
    }
    if (message == null ||
        message.groupId != continuation.groupId ||
        message.isIncoming) {
      _clearRestoredMediaContinuationTracking();
      return (handled: false, continuation: null);
    }

    if (message.status != 'failed') {
      await _clearRestoredComposerAfterSettledContinuation(message);
      return (handled: true, continuation: null);
    }

    final sameStoredDraft = message.text == continuation.draftText;
    final sameStoredQuote = _sameOptionalMessageId(
      message.quotedMessageId,
      continuation.quotedMessageId,
    );
    final sameStoredTimestamp = message.timestamp.toUtc().isAtSameMomentAs(
      continuation.timestamp.toUtc(),
    );
    if (!sameStoredDraft || !sameStoredQuote || !sameStoredTimestamp) {
      _clearRestoredMediaContinuationTracking();
      return (handled: false, continuation: null);
    }

    return (handled: false, continuation: continuation);
  }

  Future<void> _clearRestoredComposerAfterSettledContinuation(
    GroupMessage message,
  ) async {
    final fallbackMedia = _mediaMap[message.id] ?? message.media;
    final hydratedMedia = await _resolveHydratedMediaForMessage(
      message.id,
      ownerMessage: message,
      fallbackMedia: fallbackMedia,
    );
    if (!mounted) return;
    _clearRestoredMediaContinuationTracking();
    setState(() {
      _draftText = '';
      _activeQuoteMessageId = null;
      _upsertMessage(message.copyWith(media: hydratedMedia));
      _updateMediaForMessage(message.id, hydratedMedia);
    });
    _updateComposerState(
      pendingAttachments: const <PendingComposerMedia>[],
      isUploading: false,
    );
  }

  Future<void> _trackRestoredMediaContinuation({
    required ConversationComposerSnapshot snapshot,
    required String messageId,
  }) async {
    final message = await widget.msgRepo.getMessage(messageId);
    if (message == null ||
        message.groupId != widget.group.id ||
        message.isIncoming ||
        message.status != 'failed') {
      _clearRestoredMediaContinuationTracking();
      return;
    }
    _restoredMediaContinuation = _RestoredGroupMediaContinuation(
      groupId: widget.group.id,
      messageId: messageId,
      timestamp: message.timestamp,
      draftText: snapshot.draftText,
      quotedMessageId: snapshot.quotedMessageId,
      attachmentFingerprint: _pendingAttachmentFingerprint(
        snapshot.pendingAttachments,
      ),
    );
  }

  void _clearRestoredMediaContinuationTracking() {
    _restoredMediaContinuation = null;
  }

  bool _isAudioAttachment(MediaAttachment attachment) {
    return attachment.mediaType == 'audio' ||
        GroupMediaMimePolicy.mediaTypeForMime(attachment.mime) == 'audio';
  }

  bool _isRetryableVoiceAttachment(MediaAttachment attachment) {
    return _isAudioAttachment(attachment) &&
        (attachment.downloadStatus == 'upload_pending' ||
            attachment.downloadStatus == 'done');
  }

  Future<void> _trackFailedVoiceContinuation({
    required String messageId,
    required DateTime timestamp,
    required String? quotedMessageId,
  }) async {
    final mediaAttachmentRepo = widget.mediaAttachmentRepo;
    if (mediaAttachmentRepo == null) {
      _clearRestoredVoiceContinuationTracking(messageId: messageId);
      return;
    }
    final message = await widget.msgRepo.getMessage(messageId);
    final attachments = await mediaAttachmentRepo.getAttachmentsForMessage(
      messageId,
      owner: MediaOwnerLane.group,
    );
    if (message == null ||
        message.groupId != widget.group.id ||
        message.isIncoming ||
        message.status != 'failed' ||
        !message.timestamp.toUtc().isAtSameMomentAs(timestamp.toUtc()) ||
        !attachments.any(_isRetryableVoiceAttachment)) {
      _clearRestoredVoiceContinuationTracking(messageId: messageId);
      return;
    }

    _restoredVoiceContinuation = _RestoredGroupVoiceContinuation(
      groupId: widget.group.id,
      messageId: messageId,
      timestamp: timestamp,
      quotedMessageId: quotedMessageId,
    );
  }

  Future<_RestoredGroupVoiceContinuation?>
  _resolveRestoredVoiceContinuationForRecordStop({
    required String? quotedMessageId,
    required _GroupConversationSendLane lane,
  }) async {
    final continuation = _restoredVoiceContinuation;
    final mediaAttachmentRepo = lane.mediaAttachmentRepository;
    if (continuation == null || mediaAttachmentRepo == null) {
      return null;
    }
    if (continuation.groupId != lane.groupId ||
        !_sameOptionalMessageId(
          continuation.quotedMessageId,
          quotedMessageId,
        )) {
      _clearRestoredVoiceContinuationTracking();
      return null;
    }

    final message = await lane.messageRepository.getMessage(
      continuation.messageId,
    );
    final attachments = await mediaAttachmentRepo.getAttachmentsForMessage(
      continuation.messageId,
      owner: MediaOwnerLane.group,
    );
    if (message == null ||
        message.groupId != continuation.groupId ||
        message.isIncoming ||
        message.status != 'failed' ||
        !message.timestamp.toUtc().isAtSameMomentAs(
          continuation.timestamp.toUtc(),
        ) ||
        !attachments.any(_isRetryableVoiceAttachment)) {
      _clearRestoredVoiceContinuationTracking();
      return null;
    }

    _clearRestoredVoiceContinuationTracking(messageId: continuation.messageId);
    return continuation;
  }

  void _clearRestoredVoiceContinuationTracking({String? messageId}) {
    final continuation = _restoredVoiceContinuation;
    if (messageId == null || continuation?.messageId == messageId) {
      _restoredVoiceContinuation = null;
    }
  }

  Future<bool?> _showAttachmentOverflowDialog({required int totalBudgetBytes}) {
    final formattedTotal = formatPendingComposerBudgetBytes(totalBudgetBytes);
    final formattedLimit = formatPendingComposerBudgetBytes(
      widget.maxAttachmentBudgetBytes,
    );
    return showDialog<bool>(
      context: context,
      builder: (context) {
        final l10n = AppLocalizations.of(context)!;
        return AlertDialog(
          title: Text(l10n.media_too_large_title),
          content: Text(
            l10n.media_too_large_prompt(formattedTotal, formattedLimit),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.btn_cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.media_compress),
            ),
          ],
        );
      },
    );
  }

  void _showAttachmentTooLargeMessage() {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          AppLocalizations.of(context)!.media_too_large_after_compress,
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<PendingComposerMedia> _preparePendingMedia(
    String path, {
    ImageQualityPreference? imageQualityPreference,
    ImageQualityPreference? videoQualityPreference,
    bool ownsProcessingLifecycle = true,
  }) async {
    // GIF is no longer special-cased on raw pre-compression bytes here; it
    // flows through the same single send-time GroupMediaSizePolicy.validateSize
    // gate as every other type, validated on final budget bytes (INV-SZ-2).
    final processor = widget.imageProcessor;
    final isVideo = processor?.isProcessableVideo(path) ?? false;
    if (isVideo && ownsProcessingLifecycle) {
      _updateComposerState(
        isProcessing: true,
        processingProgress: 0.0,
        processingCurrent: 0,
        processingTotal: 0,
      );
    }

    try {
      return await preparePendingComposerMedia(
        inputPath: path,
        imageProcessor: processor,
        imageQualityPreference:
            imageQualityPreference ?? widget.qualityPreference,
        videoQualityPreference:
            videoQualityPreference ?? widget.videoQualityPreference,
        onVideoProgress: (progress) {
          if (mounted) {
            _updateComposerState(processingProgress: progress / 100.0);
          }
        },
      );
    } finally {
      if (isVideo && ownsProcessingLifecycle && mounted) {
        _updateComposerState(
          isProcessing: false,
          processingProgress: 0.0,
          processingCurrent: 0,
          processingTotal: 0,
        );
      }
    }
  }

  Future<void> _loadIdentity() async {
    try {
      final identity = await widget.identityRepo.loadIdentity();
      if (identity != null && mounted) {
        setState(() {
          _ownPeerId = identity.peerId;
          _senderUsername = identity.username;
          _senderPublicKey = identity.publicKey;
          _senderPrivateKey = identity.privateKey;
        });
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_CONV_FL_LOAD_IDENTITY_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _loadSecurityStatus() async {
    try {
      final identity = !_hasCompleteSenderIdentity
          ? await widget.identityRepo.loadIdentity()
          : null;
      final ownPeerId = _ownPeerId ?? identity?.peerId;
      final latestKey = await widget.groupRepo.getLatestKey(widget.group.id);
      final members = await widget.groupRepo.getMembers(widget.group.id);
      final isCurrentUserActiveMember =
          ownPeerId == null ||
          members.isEmpty ||
          members.any((member) => member.peerId == ownPeerId);
      final memberSafety = <GroupMemberIdentitySafety>[];
      for (final member in members) {
        if (member.peerId == ownPeerId) {
          continue;
        }
        try {
          final contact = await widget.contactRepo.getContact(member.peerId);
          final safety = await resolveGroupMemberDeviceSafety(
            member: member,
            savedContact: contact,
            snapshotRepo: asGroupMemberDeviceSnapshotRepository(
              widget.groupRepo,
            ),
          );
          if (safety != null) {
            memberSafety.add(safety);
          }
        } catch (e) {
          emitFlowEvent(
            layer: 'FL',
            event: 'GROUP_CONV_FL_SECURITY_MEMBER_SAFETY_ERROR',
            details: {
              'peerId': member.peerId.length > 10
                  ? member.peerId.substring(0, 10)
                  : member.peerId,
              'error': e.toString(),
            },
          );
        }
      }
      final securityStatus = GroupSecurityStatusViewState.fromSnapshot(
        latestKey: latestKey,
        memberCount: members.length,
        memberSafety: memberSafety,
        locallyVerifiedMemberCount:
            ownPeerId != null &&
                members.any((member) => member.peerId == ownPeerId)
            ? 1
            : 0,
      );
      if (!mounted) return;
      final hadWriteAccess = _canWrite;
      setState(() {
        if (identity != null) {
          _ownPeerId = identity.peerId;
          _senderUsername = identity.username;
          _senderPublicKey = identity.publicKey;
          _senderPrivateKey = identity.privateKey;
        }
        _membersByPeerId = {
          for (final member in members) member.peerId: member,
        };
        _securityStatus = securityStatus;
        _isCurrentUserActiveMember = isCurrentUserActiveMember;
        _hasCurrentSendKey = latestKey != null;
        _securityStatusLoaded = true;
      });
      if (hadWriteAccess && !_canWrite) {
        _forceCancelActiveRecording();
      }
      _maybeReleaseRecoveredTerminalReadOnly(members: members);
      _hydrateTerminalReadOnlyFromState();
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_CONV_FL_SECURITY_STATUS_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  void _recordMessageMutation(String messageId) {
    _messageMutationGeneration++;
    _messageMutationGenerations[messageId] = _messageMutationGeneration;
  }

  bool _messageMutatedAfter(String messageId, int generation) =>
      (_messageMutationGenerations[messageId] ?? 0) > generation;

  Future<void> _loadMessages() async {
    final loadGeneration = ++_messageLoadGeneration;
    final loadGroupId = widget.group.id;
    final mutationGenerationAtStart = _messageMutationGeneration;
    _messageLoadsInFlight++;
    _activeMessageLoadGenerations.add(loadGeneration);
    var appliedMessages = false;
    try {
      final messages = await widget.msgRepo.getMessagesPage(loadGroupId);
      final historyGapRepair = await widget.historyGapRepairRepo
          ?.getLatestRepairForGroup(loadGroupId);
      if (!mounted ||
          widget.group.id != loadGroupId ||
          _group.id != loadGroupId) {
        return;
      }

      final pageMessages = messages
          .where((message) => message.groupId == loadGroupId)
          .toList(growable: false);
      final mediaMap = await _loadResolvedMediaMap(pageMessages);
      if (!mounted ||
          widget.group.id != loadGroupId ||
          _group.id != loadGroupId) {
        return;
      }

      final replayAnchor =
          _sharedMediaAnchorReplayLoadGenerations.contains(loadGeneration) &&
          _sharedMediaAnchorReplayGroupId == loadGroupId &&
          _sharedMediaAnchorReplayTargetId == _activeSharedMediaAnchorTargetId;
      final appliedMessageById = <String, GroupMessage>{
        for (final message in pageMessages)
          if (!_locallyRemovedMessageIds.contains(message.id))
            message.id: message,
      };
      final appliedMediaMap = Map<String, List<MediaAttachment>>.from(mediaMap);
      var replayInjectedIds = const <String>{};
      if (replayAnchor) {
        final latestIds = appliedMessageById.keys.toSet();
        for (final message in _sharedMediaAnchorReplayWindow) {
          if (message.groupId == loadGroupId &&
              !_locallyRemovedMessageIds.contains(message.id)) {
            // The bounded around-anchor query is authoritative for its rows.
            // It completed after this latest-page load had already started, so
            // its snapshot wins any overlap while the late commit is fenced.
            appliedMessageById[message.id] = message;
          }
        }
        for (final entry in _sharedMediaAnchorReplayMedia.entries) {
          if (appliedMessageById.containsKey(entry.key) &&
              !_locallyRemovedMessageIds.contains(entry.key)) {
            appliedMediaMap[entry.key] = entry.value;
          }
        }
        replayInjectedIds = _sharedMediaAnchorReplayWindow
            .where((message) => message.groupId == loadGroupId)
            .map((message) => message.id)
            .where((messageId) => !latestIds.contains(messageId))
            .toSet();
      }

      // A live/local mutation that landed after this page load started is
      // newer authority than both its page snapshot and a captured anchor
      // window. Overlay mounted rows and media last so a late commit cannot
      // roll back delivery state or a recovered/quarantined local copy.
      final currentRowsById = <String, GroupMessage>{
        for (final message in _messages)
          if (message.groupId == loadGroupId &&
              !_locallyRemovedMessageIds.contains(message.id) &&
              _messageMutatedAfter(message.id, mutationGenerationAtStart))
            message.id: message,
      };
      appliedMessageById.addAll(currentRowsById);
      for (final messageId in currentRowsById.keys) {
        final currentMedia = _mediaMap[messageId];
        if (currentMedia == null) {
          appliedMediaMap.remove(messageId);
        } else {
          appliedMediaMap[messageId] = currentMedia;
        }
      }
      for (final messageId in _locallyRemovedMessageIds) {
        appliedMessageById.remove(messageId);
        appliedMediaMap.remove(messageId);
        replayInjectedIds = <String>{...replayInjectedIds}..remove(messageId);
      }
      final committedMessages = orderGroupMessagesForTimeline(
        appliedMessageById.values,
      );

      setState(() {
        // Apply the same quote-threaded ordering that _upsertMessage uses, so
        // the initial render order matches every subsequent in-place update and
        // no row reshuffles on the first send/receive. (The repository already
        // orders today; this keeps the two paths in lockstep defensively.)
        _messages = committedMessages;
        _mediaMap = appliedMediaMap;
        if (replayAnchor) {
          _activeSharedMediaAnchorInjectedIds = replayInjectedIds;
        } else if (_activeSharedMediaAnchorGroupId == loadGroupId) {
          // A load that started after the anchor resolved is a fresh page, not
          // part of the bounded replay fence. It may retire anchor-only rows.
          _activeSharedMediaAnchorInjectedIds = const <String>{};
          final activeTargetId = _activeSharedMediaAnchorTargetId;
          if (activeTargetId != null &&
              !appliedMessageById.containsKey(activeTargetId)) {
            if (_highlightedMessageId == activeTargetId) {
              _highlightedMessageId = null;
              _highlightScrollResolved = false;
            }
            _activeSharedMediaAnchorGroupId = null;
            _activeSharedMediaAnchorTargetId = null;
            _invalidateSharedMediaAnchorReplay();
          }
        }
        _initialLoadDone = true;
        _messageLoadErrorText = null;
        _historyGapRepair = historyGapRepair;
      });
      appliedMessages = true;
      _consumeSharedMediaAnchorReplay(loadGeneration);
      await _replayInsertedMessagesAfterLoad(
        loadedMessages: pageMessages,
        loadGeneration: loadGeneration,
      );
      // 144 finding: a persisted terminal send_failed bubble must reconstruct
      // its read-only latch on reopen. Re-run after the rows load (the security
      // status may have completed first, before _messages was populated).
      _hydrateTerminalReadOnlyFromState();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _emitNotificationTapTimingIfNeeded();
        _scrollToHighlightedMessage();
      });

      unawaited(_loadReactions(committedMessages));
      unawaited(_downloadPendingMedia(appliedMediaMap));
      await _markVisibleReadIfAllowed();
    } catch (e) {
      if (mounted) {
        setState(() {
          _initialLoadDone = true;
          if (!appliedMessages && _messages.isEmpty) {
            _messageLoadErrorText = _messageLoadErrorCopy;
          }
        });
      }
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_CONV_FL_LOAD_MESSAGES_ERROR',
        details: {'error': e.toString()},
      );
    } finally {
      _activeMessageLoadGenerations.remove(loadGeneration);
      _consumeSharedMediaAnchorReplay(loadGeneration);
      _messageLoadsInFlight--;
      if (_messageLoadsInFlight == 0) {
        _insertedIdsDuringMessageLoad.clear();
      }
    }
  }

  Future<void> _replayInsertedMessagesAfterLoad({
    required List<GroupMessage> loadedMessages,
    required int loadGeneration,
  }) async {
    if (_insertedIdsDuringMessageLoad.isEmpty) return;
    final loadedIds = loadedMessages.map((message) => message.id).toSet();
    final missingIds = _insertedIdsDuringMessageLoad
        .where((messageId) => !loadedIds.contains(messageId))
        .toList(growable: false);
    for (final messageId in missingIds) {
      if (!mounted || loadGeneration > _messageLoadGeneration) return;
      await _hydrateInsertedOutgoingMessage(messageId);
    }
  }

  Future<void> _retryMessageLoad() async {
    if (mounted) {
      setState(() {
        _messageLoadErrorText = null;
        if (_messages.isEmpty) {
          _initialLoadDone = false;
        }
      });
    }
    await _loadMessages();
  }

  Future<void> _downloadPendingMedia(
    Map<String, List<MediaAttachment>> mediaMap,
  ) async {
    final coordinator = widget.groupMediaDownloadCoordinator;
    if (coordinator != null) {
      await _recoverPendingMediaWithCoordinator(mediaMap, coordinator);
      return;
    }
    if (widget.mediaFileManager == null || widget.mediaAttachmentRepo == null) {
      return;
    }
    for (final entry in mediaMap.entries) {
      for (final attachment in entry.value) {
        if (!_shouldRecoverVisibleAttachment(attachment)) {
          continue;
        }
        // 229: consult the user policy immediately before transfer — BEFORE
        // the optimistic downloading flip, so a denied attachment keeps its
        // persisted state untouched and stays explicitly retryable.
        if (!await _autoDownloadAllowed(attachment)) {
          continue;
        }
        final currentParent = await widget.msgRepo.getMessage(entry.key);
        if (currentParent == null ||
            currentParent.groupId != _group.id ||
            !currentParent.privateMediaPolicy.isOrdinary) {
          continue;
        }

        final retrying = attachment.copyWith(
          clearLocalPath: true,
          downloadStatus: kMediaDownloadStatusDownloading,
        );
        try {
          await widget.mediaAttachmentRepo!.saveAttachment(
            retrying,
            owner: MediaOwnerLane.group,
          );
        } catch (_) {}
        if (mounted) {
          setState(() {
            final list = _replaceAttachment(
              _mediaMap[entry.key] ?? entry.value,
              retrying,
            );
            _updateMediaForMessage(entry.key, list);
          });
        }

        MediaAttachment? downloaded;
        try {
          downloaded = await downloadMedia(
            bridge: widget.bridge,
            mediaAttachmentRepo: widget.mediaAttachmentRepo!,
            mediaFileManager: widget.mediaFileManager!,
            attachment: retrying,
            contactPeerId: widget.group.id,
            enforceGroupMediaPolicy: true,
            owner: MediaOwnerLane.group,
            groupMessageRepo: widget.msgRepo,
          );
        } catch (_) {
          downloaded = null;
        }
        MediaAttachment fallbackAttachment;
        if (downloaded != null) {
          fallbackAttachment = downloaded;
        } else {
          // downloadMedia persisted the authoritative status (a bounded
          // `failed` while under budget, or the terminal `download_failed`
          // once the budget is exhausted / on a relay not-found). Re-read it so
          // the UI never downgrades a terminal row back to a retryable `failed`
          // — that would re-arm recovery forever (INV-DL-1).
          MediaAttachment? persisted;
          try {
            final rows = await widget.mediaAttachmentRepo!
                .getAttachmentsForMessage(
                  entry.key,
                  owner: MediaOwnerLane.group,
                );
            final matches = rows.where((a) => a.id == attachment.id);
            persisted = matches.isEmpty ? null : matches.first;
          } catch (_) {}
          fallbackAttachment =
              persisted ??
              retrying.copyWith(
                clearLocalPath: true,
                downloadStatus: kMediaDownloadStatusFailed,
              );
        }
        final fallbackList = _replaceAttachment(
          _mediaMap[entry.key] ?? entry.value,
          fallbackAttachment,
        );
        final resolved = await _resolveHydratedMediaForMessage(
          entry.key,
          fallbackMedia: fallbackList,
        );
        if (mounted) {
          setState(() => _updateMediaForMessage(entry.key, resolved));
        }
      }
    }
  }

  Future<void> _recoverPendingMediaWithCoordinator(
    Map<String, List<MediaAttachment>> mediaMap,
    GroupMediaDownloadCoordinator coordinator,
  ) async {
    final recoveryGroupId = _group.id;
    final attachmentIds = <String>{};
    final targetMessageIds = <String>{};
    for (final entry in mediaMap.entries) {
      final eligibleIds = entry.value
          .where(_shouldRecoverVisibleAttachment)
          .map((attachment) => attachment.id)
          .where((attachmentId) => attachmentId.isNotEmpty)
          .toSet();
      if (eligibleIds.isEmpty) continue;

      final currentParent = await widget.msgRepo.getMessage(entry.key);
      if (currentParent == null ||
          currentParent.groupId != recoveryGroupId ||
          !currentParent.isIncoming ||
          !currentParent.privateMediaPolicy.isOrdinary) {
        continue;
      }
      attachmentIds.addAll(eligibleIds);
      targetMessageIds.add(currentParent.id);
    }
    if (attachmentIds.isEmpty ||
        !mounted ||
        widget.group.id != recoveryGroupId ||
        _group.id != recoveryGroupId) {
      return;
    }

    final result = await coordinator.recoverAttachments(
      groupId: recoveryGroupId,
      attachmentIds: attachmentIds,
    );
    if (!mounted ||
        widget.group.id != recoveryGroupId ||
        _group.id != recoveryGroupId) {
      return;
    }

    // Re-read both successful messages and attempted visible parents. The
    // transfer boundary can truthfully persist a failed/quarantined state while
    // returning null, which still needs to replace the optimistic UI snapshot.
    final messagesToRehydrate = <String>{
      ...targetMessageIds,
      ...result.affectedMessageIds,
    };
    for (final messageId in messagesToRehydrate) {
      final currentParent = await widget.msgRepo.getMessage(messageId);
      if (!mounted ||
          widget.group.id != recoveryGroupId ||
          _group.id != recoveryGroupId) {
        return;
      }
      if (currentParent == null ||
          currentParent.groupId != recoveryGroupId ||
          !currentParent.isIncoming ||
          !currentParent.privateMediaPolicy.isOrdinary ||
          !_messages.any((message) => message.id == messageId)) {
        continue;
      }
      await _refreshMessageWithHydratedMedia(messageId);
    }
  }

  /// 229: the product kind this screen decides downloads under. Announcement
  /// groups are their own preference lane; chat and Q&A groups are
  /// discussions. Storage stays [MediaOwnerLane.group] for all of them —
  /// announcement is never a third storage owner.
  MediaConversationKind get _mediaConversationKind =>
      _group.type == GroupType.announcement
      ? MediaConversationKind.announcement
      : MediaConversationKind.discussion;

  /// 229: policy check run immediately before each automatic group transfer.
  /// An untrusted-row policy throw fails closed (no transfer).
  Future<bool> _autoDownloadAllowed(MediaAttachment attachment) async {
    final decider =
        widget.autoDownloadDecider ?? defaultMediaAutoDownloadDecider;
    if (decider == null) return true;
    try {
      return await decider.shouldAutoDownload(
        conversationKind: _mediaConversationKind,
        storageOwner: MediaOwnerLane.group,
        mediaType: attachment.mediaType,
        downloadStatus: attachment.downloadStatus,
      );
    } catch (_) {
      return false;
    }
  }

  void _startListening() {
    _messageSubscription = widget.groupMessageListener.groupMessageStream.listen(
      (message) {
        if (message.groupId == widget.group.id) {
          unawaited(_applyMessageUpdate(message));
          if (message.id.startsWith('sys-group_metadata_updated:') ||
              message.id.startsWith('sys-group_dissolved:') ||
              message.id.startsWith('sys-member_role_updated:')) {
            // Group-row changes (name/avatar, dissolve, self's role for the
            // announcement gate) reload the visible group row.
            unawaited(_refreshVisibleGroup());
          }
          if (message.id.startsWith('sys-members_added:') ||
              message.id.startsWith('sys-member_added:') ||
              message.id.startsWith('sys-member_removed:') ||
              message.id.startsWith('sys-member_joined:') ||
              message.id.startsWith('sys-member_role_updated:')) {
            // B5: a live membership/role change must recompute composer
            // write-access WITHOUT requiring the user to leave and re-enter.
            // _refreshVisibleGroup only reloads the group row;
            // _loadSecurityStatus re-derives _isCurrentUserActiveMember and
            // _hasCurrentSendKey and setStates them — making the composer
            // reappear on a live re-add (B3) and disappear on a live
            // removal (B2).
            unawaited(_loadSecurityStatus());
          }
        }
      },
      onError: (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_CONV_FL_STREAM_ERROR',
          details: {'error': error.toString()},
        );
      },
    );

    _removedSubscription = widget.groupMessageListener.groupRemovedStream
        .listen((groupId) {
          if (groupId != widget.group.id || !mounted) return;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            unawaited(_handleCurrentGroupRemoved());
          });
          // 158: the chat-surface ambient idle-glow is now suppressed, so an
          // otherwise-idle conversation schedules no frames on its own. A
          // removed event does not mutate the visible tree before the
          // post-frame callback fires, and addPostFrameCallback does NOT
          // request a frame — so explicitly schedule one to guarantee the
          // deferred removal handler (read-only flip / route pop) runs
          // promptly. Previously the always-on ambient loop incidentally kept
          // frames coming.
          WidgetsBinding.instance.scheduleFrame();
        });
  }

  void _restartOutgoingLocalMessageChangeSubscription() {
    unawaited(_outgoingLocalMessageChangeSubscription?.cancel());
    _outgoingLocalMessageChangeSubscription = null;
    _startListeningForOutgoingLocalMessageChanges();
  }

  void _startListeningForOutgoingLocalMessageChanges() {
    final source = widget.msgRepo is GroupOutgoingLocalMessageChangeSource
        ? widget.msgRepo as GroupOutgoingLocalMessageChangeSource
        : null;
    if (source == null) return;
    _outgoingLocalMessageChangeSubscription = source.outgoingLocalMessageChanges
        .listen(
          _handleOutgoingLocalMessageChange,
          onError: (error) {
            emitFlowEvent(
              layer: 'FL',
              event: 'GROUP_CONV_FL_LOCAL_STATUS_STREAM_ERROR',
              details: {'error': error.toString()},
            );
          },
        );
  }

  void _handleOutgoingLocalMessageChange(
    GroupOutgoingLocalMessageChange change,
  ) {
    if (!mounted) return;
    final eventGroupId = change.groupId;
    if (eventGroupId != null && eventGroupId != widget.group.id) {
      return;
    }

    if (change.reloadRequired) {
      unawaited(_loadMessages());
      return;
    }

    if (eventGroupId != widget.group.id) return;
    final messageId = change.messageId;
    final status = change.status;
    if (messageId == null) return;
    if (change.isInserted) {
      if (_messageLoadsInFlight > 0) {
        _insertedIdsDuringMessageLoad.add(messageId);
      }
      unawaited(_hydrateInsertedOutgoingMessage(messageId));
      return;
    }
    if (status == null) return;
    _updateLocalMessageStatus(messageId, status);
  }

  Future<void> _hydrateInsertedOutgoingMessage(String messageId) async {
    if (!mounted || _messages.any((message) => message.id == messageId)) {
      return;
    }
    final message = await widget.msgRepo.getMessage(messageId);
    if (message == null || message.groupId != widget.group.id || !mounted) {
      return;
    }
    final media = await _loadResolvedAttachmentsForMessage(messageId);
    final latestMessage = await widget.msgRepo.getMessage(messageId);
    if (latestMessage == null ||
        latestMessage.groupId != widget.group.id ||
        !mounted ||
        _messages.any((entry) => entry.id == messageId)) {
      return;
    }
    _enqueueGroupMessageUpdate(
      latestMessage.copyWith(media: media),
      media: media,
      markAsRead: false,
    );
  }

  Future<void> _handleCurrentGroupRemoved() async {
    if (!mounted) return;

    widget.groupConversationTracker?.clearIfActive(_activeGroupConversationKey);
    // 151: B5/B3 RETAINS a removed member's group read-only instead of
    // hard-deleting it. If the group row still exists, keep the viewer on the
    // conversation in-place as read-only (refresh row + messages + security
    // gates) — the persistent read-only banner is the durable feedback, so the
    // retained path shows NO transient "you were removed" snackbar. Resolve the
    // retain-vs-pop decision BEFORE any snackbar so the toast is scoped to the
    // hard-delete/pop branch (where there is no surface left to host a banner).
    final retainedGroup = await widget.groupRepo.getGroup(widget.group.id);
    if (!mounted) return;
    if (retainedGroup != null) {
      await _refreshVisibleGroup();
      await _loadMessages();
      await _loadSecurityStatus();
      return;
    }
    if (!mounted) return;
    // Hard-deleted (e.g. a legacy quiet-group cleanup path): no banner surface
    // survives the pop, so the snackbar is the only feedback here.
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.group_removed_snackbar),
        behavior: SnackBarBehavior.floating,
      ),
    );
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  static const _uuid = Uuid();

  bool get _supportsDurableGroupMediaUploads =>
      widget.mediaAttachmentRepo != null && widget.mediaFileManager != null;

  GroupUploadRetryProjectionRepository? get _uploadRetryProjection =>
      widget.uploadRetryProjectionRepo ??
      (widget.msgRepo is GroupUploadRetryProjectionRepository
          ? widget.msgRepo as GroupUploadRetryProjectionRepository
          : null);

  Future<List<_PreparedGroupMediaUpload>> _prepareDurableGroupMediaUploads({
    required _GroupConversationSendLane lane,
    required ConversationUploadOperation<ConversationComposerSnapshot>
    operation,
    required String messageId,
    required List<PendingComposerMedia> mediaToUpload,
    required List<String> attachmentIds,
  }) async {
    final mediaAttachmentRepo = lane.mediaAttachmentRepository;
    final mediaFileManager = lane.mediaFileManager;
    if (mediaAttachmentRepo == null || mediaFileManager == null) {
      return const [];
    }

    final createdAt = DateTime.now().toUtc().toIso8601String();
    final preparedUploads = <_PreparedGroupMediaUpload>[];

    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_CONV_FL_MEDIA_DURABLE_PREP_START',
      details: {
        'messageId': messageId.length > 8
            ? messageId.substring(0, 8)
            : messageId,
        'mediaCount': mediaToUpload.length,
      },
    );

    if (attachmentIds.length != mediaToUpload.length) {
      throw StateError('group media attachment identity count mismatch');
    }
    for (var index = 0; index < mediaToUpload.length; index++) {
      if (!_canContinueSendOperation(lane, operation)) {
        return const [];
      }
      final pending = mediaToUpload[index];
      final mime = _mimeFromPath(pending.file.path);
      final validation = await GroupMediaMimePolicy.validateFile(
        path: pending.file.path,
        mime: mime,
        mediaType: GroupMediaMimePolicy.mediaTypeForMime(mime),
      );
      if (!_canContinueSendOperation(lane, operation)) {
        return const [];
      }
      if (!validation.isValid) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_CONV_FL_MEDIA_DURABLE_PREP_REJECTED_INVALID_FILE',
          details: {'mime': mime, 'reason': validation.reason},
        );
        throw const _RejectedPendingGroupMediaException();
      }
      final sizeValidation = GroupMediaSizePolicy.validateSize(
        sizeBytes: pending.budgetBytes,
        mime: mime,
      );
      if (!sizeValidation.isValid) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_CONV_FL_MEDIA_DURABLE_PREP_REJECTED_INVALID_SIZE',
          details: {'mime': mime, 'reason': sizeValidation.reason},
        );
        throw const _RejectedPendingGroupMediaException();
      }
      final blobId = attachmentIds[index];
      final durableRelativePath = await mediaFileManager.copyToDurableStorage(
        sourceFilePath: pending.file.path,
        messageId: messageId,
        attachmentId: blobId,
        mime: mime,
      );
      if (!_canContinueSendOperation(lane, operation)) {
        return const [];
      }
      final absoluteDurablePath = await mediaFileManager.resolveStoredPath(
        durableRelativePath,
      );
      if (!_canContinueSendOperation(lane, operation)) {
        return const [];
      }
      final contentHash = await GroupMediaIntegrityPolicy.computeFileSha256Hex(
        absoluteDurablePath,
      );
      if (!_canContinueSendOperation(lane, operation)) {
        return const [];
      }
      final pendingAttachment = MediaAttachment(
        id: blobId,
        messageId: messageId,
        mime: mime,
        size: pending.budgetBytes,
        mediaType: MediaAttachment.mediaTypeFromMime(mime),
        width: pending.width,
        height: pending.height,
        durationMs: pending.durationMs,
        localPath: durableRelativePath,
        downloadStatus: 'upload_pending',
        createdAt: createdAt,
        uploadRetryCount: 0,
        downloadRetryCount: 0,
        contentHash: contentHash,
        ownerLane: MediaOwnerLane.group,
      );
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_CONV_FL_MEDIA_DURABLE_ROW_PREPARED',
        details: {
          'messageId': messageId.length > 8
              ? messageId.substring(0, 8)
              : messageId,
          'blobId': blobId.length > 8 ? blobId.substring(0, 8) : blobId,
        },
      );
      preparedUploads.add(
        _PreparedGroupMediaUpload(
          source: pending,
          pendingAttachment: pendingAttachment,
          absoluteDurablePath: absoluteDurablePath,
        ),
      );
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_CONV_FL_MEDIA_DURABLE_PREP_DONE',
      details: {'preparedCount': preparedUploads.length},
    );

    return preparedUploads;
  }

  Future<ForegroundGroupUploadLeafResult?> _runForegroundGroupUploadLeaf({
    required _GroupConversationSendLane lane,
    required GroupMessage expectedParent,
    required MediaAttachment expectedAttachment,
    required Future<UploadMediaOutcome> Function(List<String> allowedPeers)
    upload,
    required Future<MediaAttachment> Function(MediaAttachment uploaded)
    buildCompleted,
    bool replaceExistingAttachments = false,
  }) => runForegroundGroupUploadLeaf(
    groupRepository: lane.groupRepository,
    groupMessageRepository: lane.messageRepository,
    mediaAttachmentRepository: lane.mediaAttachmentRepository!,
    expectedParent: expectedParent,
    expectedAttachment: expectedAttachment,
    senderPeerId: lane.senderPeerId,
    upload: upload,
    buildCompleted: buildCompleted,
    privateMediaAvailability: lane.privateMediaAvailability,
    inviteDeliveryAttemptRepository: lane.inviteDeliveryAttemptRepository,
    uploadRetryProjectionRepository: lane.uploadRetryProjectionRepository,
    deleteReplacedAttachmentFile: (attachment) =>
        _deleteUnsafeLocalMediaFileWithManager(
          attachment,
          lane.mediaFileManager,
        ),
    replaceExistingAttachments: replaceExistingAttachments,
  );

  Future<List<MediaAttachment>?> _uploadPreparedGroupMediaUploads({
    required _GroupConversationSendLane lane,
    required GroupMessage expectedParent,
    required List<_PreparedGroupMediaUpload> preparedUploads,
    required bool replaceExistingAttachments,
    required ConversationUploadOperation<ConversationComposerSnapshot>
    operation,
  }) async {
    final mediaAttachmentRepo = lane.mediaAttachmentRepository;
    final mediaFileManager = lane.mediaFileManager;
    if (mediaAttachmentRepo == null || mediaFileManager == null) {
      return null;
    }
    if (!_canContinueSendOperation(lane, operation)) {
      return const [];
    }

    final fileSizes = <String, int>{};
    final totalBytes = preparedUploads.fold<int>(0, (sum, plan) {
      final fileSize = plan.source.budgetBytes;
      fileSizes[plan.pendingAttachment.id] = fileSize;
      return sum + fileSize;
    });

    await _startRelayUploadTracking(totalBytes, operation: operation);
    _lastUploadProjectionTerminal = false;
    final uploadResults = <ForegroundGroupUploadLeafResult?>[];
    try {
      for (var index = 0; index < preparedUploads.length; index++) {
        if (!_canContinueSendOperation(lane, operation)) {
          return const [];
        }
        if (_uploadActivityController.cancellationRequestedFor(operation)) {
          await _cancelActiveAttachmentUploadIfRequested(operation);
          return const [];
        }
        final plan = preparedUploads[index];
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_CONV_FL_MEDIA_UPLOAD_START',
          details: {
            'messageId': expectedParent.id.length > 8
                ? expectedParent.id.substring(0, 8)
                : expectedParent.id,
            'blobId': plan.pendingAttachment.id.length > 8
                ? plan.pendingAttachment.id.substring(0, 8)
                : plan.pendingAttachment.id,
          },
        );
        _markRelayUploadStarted(operation, plan.pendingAttachment.id);
        final result = await _runForegroundGroupUploadLeaf(
          lane: lane,
          expectedParent: expectedParent,
          expectedAttachment: plan.pendingAttachment,
          upload: (allowedPeers) => runUploadMedia(
            uploadMediaFn: lane.uploadMedia,
            bridge: lane.bridge,
            localFilePath: plan.absoluteDurablePath,
            mime: plan.pendingAttachment.mime,
            recipientPeerId: lane.groupId,
            mediaFileManager: mediaFileManager,
            width: plan.source.width,
            height: plan.source.height,
            durationMs: plan.source.durationMs,
            allowedPeers: allowedPeers,
            blobId: plan.pendingAttachment.id,
          ),
          buildCompleted: (uploaded) => _buildStableUploadedAttachmentFromPlan(
            lane: lane,
            messageId: expectedParent.id,
            plan: plan,
            uploaded: uploaded,
          ),
          replaceExistingAttachments: replaceExistingAttachments && index == 0,
        );
        if (!_canContinueSendOperation(lane, operation)) {
          return const [];
        }
        if (_uploadActivityController.cancellationRequestedFor(operation)) {
          await _cancelActiveAttachmentUploadIfRequested(operation);
          return const [];
        }
        uploadResults.add(result);
        if (result == null) return null;
        if (result.completedAttachment != null) {
          _markRelayUploadCompleted(
            operation,
            fileSizes[plan.pendingAttachment.id] ?? 0,
          );
        }
        if (result.completedAttachment == null) {
          final terminal = result.failureProjection?.isTerminal ?? false;
          _lastUploadProjectionTerminal |= terminal;
          if (terminal) return null;
        }
      }
    } finally {
      await _stopRelayUploadTracking(operation);
    }

    if (_uploadActivityController.cancellationRequestedFor(operation)) {
      await _cancelActiveAttachmentUploadIfRequested(operation);
      return const [];
    }

    final completedAttachments = <MediaAttachment>[];
    var failed = false;
    for (var index = 0; index < uploadResults.length; index++) {
      final result = uploadResults[index];
      if (result == null) return null;
      final completed = result.completedAttachment;
      if (completed == null) {
        failed = true;
        _lastUploadProjectionTerminal |=
            result.failureProjection?.isTerminal ?? false;
      } else {
        completedAttachments.add(completed);
      }
    }

    return failed ? null : completedAttachments;
  }

  Future<MediaAttachment> _buildStableUploadedAttachmentFromPlan({
    required _GroupConversationSendLane lane,
    required String messageId,
    required _PreparedGroupMediaUpload plan,
    required MediaAttachment uploaded,
  }) async {
    final mediaFileManager = lane.mediaFileManager;
    final sourceFile = File(plan.absoluteDurablePath);
    final contentHash =
        uploaded.contentHash ??
        plan.pendingAttachment.contentHash ??
        (await sourceFile.exists()
            ? await GroupMediaIntegrityPolicy.computeFileSha256Hex(
                plan.absoluteDurablePath,
              )
            : null);
    if (mediaFileManager == null) {
      return uploaded.copyWith(
        id: plan.pendingAttachment.id,
        messageId: messageId,
        size: uploaded.size > 0 ? uploaded.size : plan.source.budgetBytes,
        mediaType: plan.pendingAttachment.mediaType,
        width: uploaded.width ?? plan.source.width,
        height: uploaded.height ?? plan.source.height,
        durationMs: uploaded.durationMs ?? plan.source.durationMs,
        localPath: plan.absoluteDurablePath,
        downloadStatus: 'done',
        uploadRetryCount: plan.pendingAttachment.uploadRetryCount,
        waveform: uploaded.waveform,
        contentHash: contentHash,
      );
    }

    final absoluteOwnedPath = await mediaFileManager.localPathForAttachment(
      contactPeerId: lane.groupId,
      blobId: plan.pendingAttachment.id,
      mime: plan.pendingAttachment.mime,
    );
    if (!await sourceFile.exists()) {
      return uploaded.copyWith(
        id: plan.pendingAttachment.id,
        messageId: messageId,
        size: uploaded.size > 0 ? uploaded.size : plan.source.budgetBytes,
        mediaType: plan.pendingAttachment.mediaType,
        width: uploaded.width ?? plan.source.width,
        height: uploaded.height ?? plan.source.height,
        durationMs: uploaded.durationMs ?? plan.source.durationMs,
        localPath: uploaded.localPath ?? plan.absoluteDurablePath,
        downloadStatus: 'done',
        uploadRetryCount: plan.pendingAttachment.uploadRetryCount,
        waveform: uploaded.waveform,
        contentHash: contentHash,
      );
    }
    if (absoluteOwnedPath != plan.absoluteDurablePath) {
      final targetFile = File(absoluteOwnedPath);
      final parent = targetFile.parent;
      if (!await parent.exists()) {
        await parent.create(recursive: true);
      }
      await sourceFile.copy(absoluteOwnedPath);
    }

    return uploaded.copyWith(
      id: plan.pendingAttachment.id,
      messageId: messageId,
      size: uploaded.size > 0 ? uploaded.size : plan.source.budgetBytes,
      mediaType: plan.pendingAttachment.mediaType,
      width: uploaded.width ?? plan.source.width,
      height: uploaded.height ?? plan.source.height,
      durationMs: uploaded.durationMs ?? plan.source.durationMs,
      localPath: mediaFileManager.relativePathForAttachment(
        contactPeerId: lane.groupId,
        blobId: plan.pendingAttachment.id,
        mime: plan.pendingAttachment.mime,
      ),
      downloadStatus: 'done',
      uploadRetryCount: plan.pendingAttachment.uploadRetryCount,
      waveform: uploaded.waveform,
      contentHash: contentHash,
    );
  }

  Future<void> _onSend(String text) async {
    if (!_canWrite) return;
    if (!await _refreshSendCapabilityAndCanWrite()) return;
    if (!_hasCompleteSenderIdentity) return;
    final sendLane = _captureSendLane();
    final sendGroupId = sendLane.groupId;

    final mediaToUpload = List<PendingComposerMedia>.from(
      _composerController.pendingAttachments,
    );
    final hasAttachments = mediaToUpload.isNotEmpty;
    if (text.isEmpty && !hasAttachments) return;
    final draftText = text;
    final quotedMessageId = _activeQuoteMessageId;
    const privateMediaPolicy = GroupPrivateMediaPolicy.ordinary();
    const privateKeyGeneration = 0;
    final restoredResolution = await _resolveRestoredMediaContinuationForSend(
      lane: sendLane,
      draftText: draftText,
      quotedMessageId: quotedMessageId,
      pendingAttachments: mediaToUpload,
    );
    if (!_isCurrentSendLane(sendLane)) return;
    if (restoredResolution.handled) return;
    if (!_validatePendingGroupMediaDescriptors(mediaToUpload)) {
      return;
    }
    if (hasAttachments) {
      final preflightMembers = await sendLane.groupRepository.getMembers(
        sendGroupId,
      );
      if (!_isCurrentSendLane(sendLane)) return;
      if (!_passesGroupMediaAclPreflight(
        preflightMembers,
        surface: 'ordinary',
      )) {
        return;
      }
    }
    if (!_tryBeginSendFlow()) return;
    final restoredContinuation = restoredResolution.continuation;
    if (restoredContinuation != null) {
      _clearRestoredMediaContinuationTracking();
    }
    final composerSnapshot = _composerController.snapshot(
      draftText: draftText,
      quotedMessageId: quotedMessageId,
    );

    // 1. Generate IDs upfront for optimistic display
    final messageId = restoredContinuation?.messageId ?? _uuid.v4();
    final now = restoredContinuation?.timestamp ?? DateTime.now().toUtc();

    // 2. Capture and clear pending attachments
    List<MediaAttachment>? optimisticMedia;
    var optimisticDisplayed = false;
    MediaUploadLease? uploadLease;

    if (mediaToUpload.isNotEmpty) {
      final createdAt = now.toIso8601String();
      optimisticMedia = mediaToUpload.map((m) {
        final mime = _mimeFromPath(m.file.path);
        return MediaAttachment(
          id: _uuid.v4(),
          messageId: messageId,
          mime: mime,
          size: 0,
          mediaType: MediaAttachment.mediaTypeFromMime(mime),
          width: m.width,
          height: m.height,
          durationMs: m.durationMs,
          localPath: m.file.path,
          downloadStatus: 'done',
          createdAt: createdAt,
        );
      }).toList();
      uploadLease = mediaUploadInFlightTracker.tryClaimAll(
        optimisticMedia.map((attachment) => attachment.id),
        source: MediaUploadTriggerSource.foreground,
      );
      if (uploadLease == null) {
        _endSendFlow();
        return;
      }
    }

    _draftText = '';
    _updateComposerState(
      pendingAttachments: const <PendingComposerMedia>[],
      isUploading: mediaToUpload.isNotEmpty,
    );
    if (_activeQuoteMessageId != null && mounted) {
      setState(() => _activeQuoteMessageId = null);
    }

    // 3. Create optimistic message and display immediately
    final optimisticMessage = GroupMessage(
      id: messageId,
      groupId: sendGroupId,
      senderPeerId: sendLane.senderPeerId,
      senderUsername: sendLane.senderUsername,
      text: text,
      timestamp: now,
      quotedMessageId: quotedMessageId,
      keyGeneration: privateKeyGeneration,
      // 210: while the sender is offline the optimistic bubble must show a CLOCK
      // from the very first frame (no 'sending' tick flash). The send result
      // handler re-affirms 'queued_offline' after the awaited send fails.
      status: sendLane.p2pService.currentState.relayReady
          ? 'sending'
          : GroupMessage.statusQueuedOffline,
      isIncoming: false,
      createdAt: now,
      privateMediaPolicy: privateMediaPolicy,
    );

    void showOptimisticMessage() {
      if (!_isCurrentSendLane(sendLane) || optimisticDisplayed) {
        return;
      }
      setState(() {
        _upsertMessage(optimisticMessage);
        final optimisticAttachments = optimisticMedia;
        if (optimisticAttachments != null && optimisticAttachments.isNotEmpty) {
          _updateMediaForMessage(messageId, optimisticAttachments);
        }
      });
      optimisticDisplayed = true;
      _scrollToLiveEdge();
    }

    // 4. sendGroupMessage() still owns the final message row save.
    final attachmentOperation = mediaToUpload.isEmpty
        ? null
        : _beginActiveAttachmentUpload(
            messageId: messageId,
            composerSnapshot: composerSnapshot,
          );
    final bgTaskId = await _beginBackgroundTaskGuarded(bridge: sendLane.bridge);
    try {
      final pendingAttachmentOperation = attachmentOperation;
      if (pendingAttachmentOperation == null) {
        if (!_canContinueSendLane(sendLane)) return;
      } else if (!_canContinueSendOperation(
        sendLane,
        pendingAttachmentOperation,
      )) {
        return;
      }
      // 5. Upload attachments (if any)
      List<MediaAttachment>? uploadedAttachments;
      if (mediaToUpload.isNotEmpty) {
        final exactAttachmentOperation = attachmentOperation!;
        final members = await sendLane.groupRepository.getMembers(sendGroupId);
        if (!_canContinueSendOperation(sendLane, exactAttachmentOperation)) {
          return;
        }
        final allowedPeers = groupMediaAllowedPeersForMembers(members);

        try {
          if (sendLane.mediaAttachmentRepository != null &&
              sendLane.mediaFileManager != null) {
            final preparedUploads = await _prepareDurableGroupMediaUploads(
              lane: sendLane,
              operation: exactAttachmentOperation,
              messageId: messageId,
              mediaToUpload: mediaToUpload,
              attachmentIds: optimisticMedia!
                  .map((attachment) => attachment.id)
                  .toList(growable: false),
            );
            if (!_canContinueSendOperation(
              sendLane,
              exactAttachmentOperation,
            )) {
              return;
            }
            await sendLane.messageRepository.saveMessage(optimisticMessage);
            if (!_canContinueSendOperation(
              sendLane,
              exactAttachmentOperation,
            )) {
              return;
            }
            optimisticMedia = preparedUploads
                .map(
                  (plan) => plan.pendingAttachment.copyWith(
                    localPath: plan.absoluteDurablePath,
                    downloadStatus: 'done',
                  ),
                )
                .toList(growable: false);
            showOptimisticMessage();
            await Future<void>.delayed(Duration.zero);
            var initialUploadQualified = false;
            uploadedAttachments =
                await runQualifiedPrivateGroupMediaInitialUpload<
                  List<MediaAttachment>
                >(
                  groupRepo: sendLane.groupRepository,
                  msgRepo: sendLane.messageRepository,
                  expectedParent: optimisticMessage,
                  senderPeerId: sendLane.senderPeerId,
                  privateMediaAvailability: sendLane.privateMediaAvailability,
                  expectedAllowedPeerIds: allowedPeers,
                  upload: () {
                    initialUploadQualified = true;
                    return _uploadPreparedGroupMediaUploads(
                      lane: sendLane,
                      expectedParent: optimisticMessage,
                      preparedUploads: preparedUploads,
                      replaceExistingAttachments: restoredContinuation != null,
                      operation: exactAttachmentOperation,
                    );
                  },
                );
            if (!_canContinueSendOperation(
              sendLane,
              exactAttachmentOperation,
            )) {
              return;
            }
            if (!initialUploadQualified) {
              await _restoreComposerSnapshotWithoutFailure(
                composerSnapshot,
                messageId,
              );
              return;
            }
            if (await _cancelActiveAttachmentUploadIfRequested(
              exactAttachmentOperation,
            )) {
              return;
            }
            if (uploadedAttachments == null) {
              if (sendLane.uploadRetryProjectionRepository != null) {
                await _applyProjectedGroupUploadFailureUi(
                  composerSnapshot,
                  messageId: messageId,
                  terminal: _lastUploadProjectionTerminal,
                );
              } else {
                await _restoreComposerSnapshot(composerSnapshot, messageId);
              }
              return;
            }
          } else {
            final optimistic = optimisticMedia!;
            optimisticMedia = optimistic;
            showOptimisticMessage();

            uploadedAttachments = [];
            var relayTrackingStarted = false;
            for (var index = 0; index < mediaToUpload.length; index++) {
              if (await _cancelActiveAttachmentUploadIfRequested(
                exactAttachmentOperation,
              )) {
                return;
              }
              final pending = mediaToUpload[index];
              final mime = _mimeFromPath(pending.file.path);
              final attachmentId = optimisticMedia[index].id;
              final fileSize = File(pending.file.path).lengthSync();
              if (!relayTrackingStarted) {
                final remainingBytes = mediaToUpload
                    .skip(index)
                    .fold<int>(
                      0,
                      (sum, item) => sum + File(item.file.path).lengthSync(),
                    );
                await _startRelayUploadTracking(
                  remainingBytes,
                  operation: exactAttachmentOperation,
                );
                relayTrackingStarted = true;
              }
              _markRelayUploadStarted(exactAttachmentOperation, attachmentId);
              final uploadOutcome = await runUploadMedia(
                uploadMediaFn: sendLane.uploadMedia,
                bridge: sendLane.bridge,
                localFilePath: pending.file.path,
                mime: mime,
                recipientPeerId: sendGroupId,
                mediaFileManager: sendLane.mediaFileManager,
                width: pending.width,
                height: pending.height,
                durationMs: pending.durationMs,
                allowedPeers: allowedPeers,
                blobId: attachmentId,
              );
              if (!_canContinueSendOperation(
                sendLane,
                exactAttachmentOperation,
              )) {
                return;
              }
              final result = uploadOutcome.attachmentOrNull;
              if (result != null) {
                _markRelayUploadCompleted(exactAttachmentOperation, fileSize);
                final contentHash =
                    result.contentHash ??
                    await GroupMediaIntegrityPolicy.computeFileSha256Hex(
                      pending.file.path,
                    );
                if (!_canContinueSendOperation(
                  sendLane,
                  exactAttachmentOperation,
                )) {
                  return;
                }
                uploadedAttachments.add(
                  result.copyWith(
                    id: attachmentId,
                    messageId: messageId,
                    downloadStatus: 'done',
                    contentHash: contentHash,
                  ),
                );
              } else {
                await _stopRelayUploadTracking(exactAttachmentOperation);
                final projection = sendLane.uploadRetryProjectionRepository;
                if (projection == null) {
                  await _restoreComposerSnapshot(composerSnapshot, messageId);
                  return;
                }
                final projected = await projection.projectUploadFailure(
                  messageId: messageId,
                  attachmentId: attachmentId,
                  failure: uploadOutcome as UploadMediaFailed,
                );
                if (!_canContinueSendOperation(
                  sendLane,
                  exactAttachmentOperation,
                )) {
                  return;
                }
                await _applyProjectedGroupUploadFailureUi(
                  composerSnapshot,
                  messageId: messageId,
                  terminal: projected.isTerminal,
                );
                return;
              }
              if (await _cancelActiveAttachmentUploadIfRequested(
                exactAttachmentOperation,
              )) {
                return;
              }
            }
            if (await _cancelActiveAttachmentUploadIfRequested(
              exactAttachmentOperation,
            )) {
              return;
            }
            await _stopRelayUploadTracking(exactAttachmentOperation);
            if (_uploadActivityController.isCurrentOperation(
                  exactAttachmentOperation,
                ) &&
                mounted) {
              _updateComposerState(isUploading: false);
            }
          }
        } finally {
          await _clearActiveAttachmentUpload(exactAttachmentOperation);
        }
      } else {
        showOptimisticMessage();
      }

      final exactAttachmentOperation = attachmentOperation;
      if (exactAttachmentOperation == null) {
        if (!_canContinueSendLane(sendLane)) return;
      } else if (!_canContinueSendOperation(
        sendLane,
        exactAttachmentOperation,
      )) {
        return;
      }

      final (result, message) = await sendGroupMessage(
        bridge: sendLane.bridge,
        groupRepo: sendLane.groupRepository,
        msgRepo: sendLane.messageRepository,
        groupId: sendGroupId,
        text: text,
        senderPeerId: sendLane.senderPeerId,
        senderPublicKey: sendLane.senderPublicKey,
        senderPrivateKey: sendLane.senderPrivateKey,
        senderUsername: sendLane.senderUsername,
        messageId: messageId,
        timestamp: now,
        quotedMessageId: quotedMessageId,
        privateMediaPolicy: privateMediaPolicy,
        privateMediaAvailability: sendLane.privateMediaAvailability,
        senderDeviceId: sendLane.senderDeviceId,
        senderTransportPeerId: sendLane.senderDeviceId,
        mediaAttachments: uploadedAttachments,
        mediaAttachmentRepo: sendLane.mediaAttachmentRepository,
        inviteDeliveryAttemptRepo: sendLane.inviteDeliveryAttemptRepository,
      );
      if (!_isCurrentSendLane(sendLane)) return;

      if ((result == SendGroupMessageResult.success ||
              result == SendGroupMessageResult.successNoPeers) &&
          message != null) {
        // Resolve uploaded media paths for display
        List<MediaAttachment>? displayMedia;
        if (uploadedAttachments != null && sendLane.mediaFileManager != null) {
          displayMedia = [];
          for (final a in uploadedAttachments) {
            if (a.localPath != null) {
              final absPath = await sendLane.mediaFileManager!
                  .resolveStoredPath(a.localPath!);
              if (!_isCurrentSendLane(sendLane)) return;
              displayMedia.add(a.copyWith(localPath: absPath));
            } else {
              displayMedia.add(a);
            }
          }
        }
        if (mounted) {
          setState(() {
            _upsertMessage(message);
            if (displayMedia != null && displayMedia.isNotEmpty) {
              _updateMediaForMessage(messageId, displayMedia);
            }
          });
        }
        if (sendLane.mediaAttachmentRepository != null &&
            sendLane.mediaFileManager != null &&
            mediaToUpload.isNotEmpty) {
          try {
            await sendLane.mediaFileManager?.deletePendingUploadDir(messageId);
          } catch (_) {}
        }
      } else if (result == SendGroupMessageResult.queuedOffline &&
          message != null) {
        // 210b: the PRIMARY offline lane. A real offline send is NOT an error —
        // the publish "succeeds" with zero live topic peers and no relay
        // custody, and the use case has already persisted the durable
        // 'queued_offline' row with its repush payload armed. Keyed off the
        // RESULT CONTRACT, not the stale-prone relayReady snapshot (the 192
        // lesson): reflect the clock on the on-screen row (it may have been
        // inserted as 'sending' during the stale-online window), keep the
        // composer clear (no Retry), and surface the honest snackbar. The
        // repush lane settles the row to 'sent' (tick) on reconnect.
        await _markOutgoingMessageQueuedOffline(messageId);
        _showOfflineQueuedSnackBar();
        // Same staging-dir cleanup as the happy branch: reaching the send with
        // uploads meant they completed durably; the queued row's repush needs
        // only the persisted payload, not the staging copies (review 210b-F6).
        if (sendLane.mediaAttachmentRepository != null &&
            sendLane.mediaFileManager != null &&
            mediaToUpload.isNotEmpty) {
          try {
            await sendLane.mediaFileManager?.deletePendingUploadDir(messageId);
          } catch (_) {}
        }
      } else if (result == SendGroupMessageResult.groupNotFound ||
          result == SendGroupMessageResult.groupDissolved ||
          result == SendGroupMessageResult.unauthorized) {
        // 144: a terminal result is durable, not transient. Keep the optimistic
        // bubble as a non-retryable send_failed row (preserving the typed text /
        // attachments) and latch the composer read-only — instead of deleting
        // the row and flashing a 4s snackbar. saveMessage upserts, so even a
        // plain-text row that was never pre-persisted survives a reopen.
        final failedMessage = optimisticMessage.copyWith(
          status: GroupMessage.statusSendFailed,
        );
        try {
          await sendLane.messageRepository.saveMessage(failedMessage);
        } catch (_) {}
        _updateLocalMessageStatus(messageId, GroupMessage.statusSendFailed);
        if (result == SendGroupMessageResult.groupDissolved) {
          // Refreshes the rest of the group UI. The read-only override below is
          // what actually flips the banner: the row is NOT marked dissolved in
          // the empty-membership case, so a membership refresh fails open.
          await _refreshVisibleGroup();
        }
        _setTerminalSendReadOnly(_terminalReadOnlyForSendResult(result));
      } else if (!sendLane.p2pService.currentState.relayReady &&
          message != null) {
        // 210: the send failed purely because WE are offline (relay
        // unreachable) and a durable row exists (message != null). Keep it as a
        // self-healing 'queued_offline' row (clock, not tick), leave the
        // composer clear (no Retry), and surface the honest offline snackbar —
        // the stuck-sending recovery sweep re-drives it on reconnect. Ordered
        // AFTER the terminal checks so a terminal group-lifecycle failure still
        // wins (error + read-only), and BEFORE the online-error restore so the
        // relayReady==true case keeps its 'failed' + composer restore.
        await _markOutgoingMessageQueuedOffline(messageId);
        _showOfflineQueuedSnackBar();
      } else if (message == null) {
        await _restoreComposerSnapshotWithoutFailure(
          composerSnapshot,
          messageId,
        );
      } else {
        await _restoreComposerSnapshot(composerSnapshot, messageId);
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_CONV_FL_SEND_ERROR',
        details: {'error': e.toString()},
      );
      await _restoreComposerSnapshot(composerSnapshot, messageId);
    } finally {
      try {
        await _clearActiveAttachmentUpload(attachmentOperation);
        await _endBackgroundTaskGuarded(bgTaskId, bridge: sendLane.bridge);
      } finally {
        final lease = uploadLease;
        if (lease != null) {
          mediaUploadInFlightTracker.release(lease);
        }
        _endSendFlow();
      }
    }
  }

  void _onDraftChanged(String text) {
    if (!_canWrite) return;
    if (_draftText == text) return;
    setState(() => _draftText = text);
    final restored = _restoredMediaContinuation;
    if (restored != null && text != restored.draftText) {
      _clearRestoredMediaContinuationTracking();
    }
  }

  Future<void> _onRetryUnavailableMedia(
    String messageId,
    String attachmentId,
  ) async {
    final mediaAttachmentRepo = widget.mediaAttachmentRepo;
    final mediaFileManager = widget.mediaFileManager;
    if (mediaAttachmentRepo == null || mediaFileManager == null) {
      _showFloatingSnackBar(
        AppLocalizations.of(context)!.media_retry_unavailable_now,
        backgroundColor: Colors.red[700],
      );
      return;
    }
    var currentParent = await widget.msgRepo.getMessage(messageId);
    if (currentParent == null ||
        currentParent.groupId != _group.id ||
        !currentParent.privateMediaPolicy.isOrdinary) {
      return;
    }

    final persisted = await mediaAttachmentRepo.getAttachmentsForMessage(
      messageId,
      owner: MediaOwnerLane.group,
    );
    final fallback = _mediaMap[messageId] ?? persisted;
    final target = persisted
        .where((attachment) => attachment.id == attachmentId)
        .firstOrNull;
    if (target == null) {
      if (!mounted) return;
      _showFloatingSnackBar(
        AppLocalizations.of(context)!.media_unavailable_now,
        backgroundColor: Colors.red[700],
      );
      return;
    }
    currentParent = await widget.msgRepo.getMessage(messageId);
    if (currentParent == null ||
        currentParent.groupId != _group.id ||
        !currentParent.privateMediaPolicy.isOrdinary) {
      return;
    }

    await _deleteUnsafeLocalMediaFile(target);

    final retrying = target.copyWith(
      clearLocalPath: true,
      downloadStatus: kMediaDownloadStatusDownloading,
    );
    await mediaAttachmentRepo.saveAttachment(
      retrying,
      owner: MediaOwnerLane.group,
    );
    if (mounted) {
      setState(() {
        _updateMediaForMessage(
          messageId,
          _replaceAttachment(fallback, retrying),
        );
      });
    }

    MediaAttachment? downloaded;
    try {
      downloaded = await downloadMedia(
        bridge: widget.bridge,
        mediaAttachmentRepo: mediaAttachmentRepo,
        mediaFileManager: mediaFileManager,
        attachment: retrying,
        contactPeerId: widget.group.id,
        enforceGroupMediaPolicy: true,
        owner: MediaOwnerLane.group,
        groupMessageRepo: widget.msgRepo,
      );
    } catch (_) {
      downloaded = null;
    }

    final resolved = await _resolveHydratedMediaForMessage(
      messageId,
      fallbackMedia: _replaceAttachment(
        fallback,
        downloaded ??
            retrying.copyWith(
              clearLocalPath: true,
              downloadStatus: kMediaDownloadStatusIntegrityFailed,
            ),
      ),
    );
    if (!mounted) return;

    setState(() => _updateMediaForMessage(messageId, resolved));
    // 149: the refreshed media's availability is now conveyed inline by the
    // MediaGridCell unavailable/retry placeholder — the redundant transient
    // "still unavailable" snackbar is dropped.
  }

  List<MediaAttachment> _replaceAttachment(
    List<MediaAttachment> attachments,
    MediaAttachment replacement,
  ) {
    final next = List<MediaAttachment>.from(attachments);
    final index = next.indexWhere(
      (attachment) => attachment.id == replacement.id,
    );
    if (index >= 0) {
      next[index] = replacement;
    } else {
      next.add(replacement);
    }
    return next;
  }

  Future<void> _deleteUnsafeLocalMediaFile(MediaAttachment attachment) =>
      _deleteUnsafeLocalMediaFileWithManager(
        attachment,
        widget.mediaFileManager,
      );

  Future<void> _deleteUnsafeLocalMediaFileWithManager(
    MediaAttachment attachment,
    MediaFileManager? mediaFileManager,
  ) async {
    final localPath = attachment.localPath;
    if (localPath == null || mediaFileManager == null) return;
    if (_isPendingUploadPath(localPath)) return;

    try {
      final absolutePath = await mediaFileManager.resolveStoredPath(localPath);
      if (_isPendingUploadPath(absolutePath)) return;
      // 229: route through the guarded app-owned delete (ownership telemetry,
      // no raw unlink) instead of a bare File.delete.
      await mediaFileManager.deleteFile(
        absolutePath,
        caller: 'GroupConversationWired._deleteUnsafeLocalMediaFile',
        reason: 'replace_unsafe_local_copy_before_retry',
        storedPath: localPath,
      );
    } catch (_) {}
  }

  Future<void> _deleteCanonicalOwnedGroupMediaFile(
    MediaAttachment attachment,
  ) async {
    final mediaFileManager = widget.mediaFileManager;
    final storedPath = attachment.localPath;
    if (mediaFileManager == null ||
        storedPath == null ||
        storedPath.isEmpty ||
        _isPendingUploadPath(storedPath) ||
        !DirectPrivateMediaPathGuard.isSafeSegment(widget.group.id) ||
        !DirectPrivateMediaPathGuard.isSafeSegment(attachment.id)) {
      return;
    }
    final canonicalStoredPath = mediaFileManager.relativePathForAttachment(
      contactPeerId: widget.group.id,
      blobId: attachment.id,
      mime: attachment.mime,
    );
    final canonicalAbsolutePath = p.normalize(
      await mediaFileManager.resolveStoredPath(canonicalStoredPath),
    );
    final storedAbsolutePath = p.normalize(
      await mediaFileManager.resolveStoredPath(storedPath),
    );
    if (storedAbsolutePath != canonicalAbsolutePath) return;
    await mediaFileManager.deleteFile(
      canonicalAbsolutePath,
      caller: 'GroupConversationWired._deleteCanonicalOwnedGroupMediaFile',
      reason: 'failed_group_media_delete',
      storedPath: storedPath,
      details: {
        'messageId': attachment.messageId,
        'attachmentId': attachment.id,
        'groupId': widget.group.id,
      },
    );
  }

  Future<void> _onRetryFailedMedia(String messageId) async {
    final mediaAttachmentRepo = widget.mediaAttachmentRepo;
    final mediaFileManager = widget.mediaFileManager;
    if (mediaAttachmentRepo == null || mediaFileManager == null) {
      _showFloatingSnackBar(
        AppLocalizations.of(context)!.media_retry_unavailable_now,
        backgroundColor: Colors.red[700],
      );
      return;
    }

    final fallbackMedia =
        _mediaMap[messageId] ??
        _messages
            .where((message) => message.id == messageId)
            .firstOrNull
            ?.media;
    final persistedMedia = await mediaAttachmentRepo.getAttachmentsForMessage(
      messageId,
      owner: MediaOwnerLane.group,
    );
    if (persistedMedia.any(
      (attachment) =>
          attachment.downloadStatus == 'upload_pending' ||
          attachment.downloadStatus == 'upload_failed',
    )) {
      if (!_tryBeginSendFlow()) return;
      _clearRestoredVoiceContinuationTracking(messageId: messageId);
      final bgTaskId = await _beginBackgroundTaskGuarded();
      try {
        await retryIncompleteGroupUploads(
          groupRepo: widget.groupRepo,
          groupMsgRepo: widget.msgRepo,
          mediaAttachmentRepo: mediaAttachmentRepo,
          bridge: widget.bridge,
          p2pService: widget.p2pService,
          identityRepo: widget.identityRepo,
          uploadMediaFn: widget.uploadMediaFn,
          mediaFileManager: mediaFileManager,
          messageId: messageId,
          privateMediaAvailability: widget.privateMediaAvailability,
          inviteDeliveryAttemptRepo: widget.inviteDeliveryAttemptRepo,
          tryClaimUploadLease: (attachmentIds) =>
              mediaUploadInFlightTracker.tryClaimAll(
                attachmentIds,
                source: MediaUploadTriggerSource.manual,
              ),
          releaseUploadLease: mediaUploadInFlightTracker.release,
          manualRetry: true,
        );
      } catch (e) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_CONV_FL_MANUAL_MEDIA_RETRY_ERROR',
          details: {'error': e.toString()},
        );
      } finally {
        try {
          await _refreshMessageWithHydratedMedia(
            messageId,
            fallbackMedia: fallbackMedia,
          );
        } finally {
          await _endBackgroundTaskGuarded(bgTaskId);
          _endSendFlow();
        }
      }
      // The upload-pending / failed state is conveyed inline by the media cell.
      return;
    }

    _clearRestoredVoiceContinuationTracking(messageId: messageId);
    await retryFailedGroupMessage(
      messageId: messageId,
      groupMsgRepo: widget.msgRepo,
      groupRepo: widget.groupRepo,
      identityRepo: widget.identityRepo,
      bridge: widget.bridge,
      mediaAttachmentRepo: mediaAttachmentRepo,
      privateMediaAvailability: widget.privateMediaAvailability,
      inviteDeliveryAttemptRepo: widget.inviteDeliveryAttemptRepo,
    );

    await _refreshMessageWithHydratedMedia(
      messageId,
      fallbackMedia: fallbackMedia,
    );
    // 149: the failed-media retry outcome is conveyed inline by the
    // MediaGridCell unavailable/retry placeholder — the redundant retry-failed
    // snackbar is dropped.
  }

  Future<void> _onRetryFailedMessage(String messageId) async {
    if (!_canWrite) return;
    if (groupRecoveryGate.activeDepthListenable.value > 0) return;
    final mediaAttachmentRepo = widget.mediaAttachmentRepo;
    if (mediaAttachmentRepo == null) {
      _showFloatingSnackBar(
        AppLocalizations.of(context)!.media_retry_unavailable_now,
        backgroundColor: Colors.red[700],
      );
      return;
    }

    if (!_tryBeginFailedMessageRetry(messageId)) return;
    try {
      final retried = await retryFailedGroupMessage(
        messageId: messageId,
        groupMsgRepo: widget.msgRepo,
        groupRepo: widget.groupRepo,
        identityRepo: widget.identityRepo,
        bridge: widget.bridge,
        mediaAttachmentRepo: mediaAttachmentRepo,
        privateMediaAvailability: widget.privateMediaAvailability,
        inviteDeliveryAttemptRepo: widget.inviteDeliveryAttemptRepo,
      );

      await _refreshMessageWithHydratedMedia(messageId);

      if (!mounted) return;
      if (retried == 0) {
        _showFloatingSnackBar(
          AppLocalizations.of(context)!.failed_message_retry_failed,
          backgroundColor: Colors.red[700],
        );
      }
    } finally {
      _endFailedMessageRetry(messageId);
    }
  }

  Future<void> _onDeleteFailedMedia(String messageId) async {
    final mediaAttachmentRepo = widget.mediaAttachmentRepo;
    final mediaFileManager = widget.mediaFileManager;
    if (mediaAttachmentRepo == null || mediaFileManager == null) {
      _showFloatingSnackBar(
        AppLocalizations.of(context)!.failed_media_delete_unavailable,
        backgroundColor: Colors.red[700],
      );
      return;
    }

    _clearRestoredVoiceContinuationTracking(messageId: messageId);
    final storedAttachments = await mediaAttachmentRepo
        .getAttachmentsForMessage(messageId, owner: MediaOwnerLane.group);
    final storedPaths = storedAttachments.map(
      (attachment) => attachment.localPath,
    );

    await mediaAttachmentRepo.markUploadPendingAttachmentsFailedForMessage(
      messageId,
      owner: MediaOwnerLane.group,
    );
    await mediaFileManager.deleteOwnedPendingUploadFilesForMessage(
      messageId: messageId,
      storedPaths: storedPaths,
    );
    await mediaAttachmentRepo.deleteAttachmentsForMessage(
      messageId,
      owner: MediaOwnerLane.group,
    );
    await widget.msgRepo.deleteMessage(messageId);

    _removeLocalMessage(messageId);
  }

  Future<void> _cleanupRestoredComposerRetryState(String messageId) async {
    try {
      await widget.mediaAttachmentRepo
          ?.markUploadPendingAttachmentsFailedForMessage(
            messageId,
            owner: MediaOwnerLane.group,
          );
    } catch (_) {}
    try {
      await widget.mediaFileManager?.deletePendingUploadDir(messageId);
    } catch (_) {}
  }

  Future<void> _markFailedTextMessageWithoutComposerRestore(
    String messageId, {
    String? snackText,
    bool showSnackBar = false,
  }) async {
    _draftText = '';
    _clearRestoredMediaContinuationTracking();
    if (mounted) {
      _updateComposerState(
        pendingAttachments: const <PendingComposerMedia>[],
        isUploading: false,
      );
    }
    _updateLocalMessageStatus(messageId, 'failed');
    if (mounted) {
      setState(() {
        _activeQuoteMessageId = null;
      });
    } else {
      _activeQuoteMessageId = null;
    }
    await _persistMessageStatus(messageId, 'failed');
    if (showSnackBar && snackText != null) {
      _showFloatingSnackBar(snackText);
    }
  }

  Future<void> _restoreComposerSnapshot(
    ConversationComposerSnapshot snapshot,
    String messageId, {
    String? snackText,
    bool showSnackBar = false,
  }) async {
    if (snapshot.pendingAttachments.isEmpty) {
      await _markFailedTextMessageWithoutComposerRestore(
        messageId,
        snackText: snackText,
        showSnackBar: showSnackBar,
      );
      return;
    }
    _draftText = snapshot.draftText;
    if (mounted) {
      _updateComposerState(
        pendingAttachments: snapshot.pendingAttachments,
        isUploading: false,
      );
    }
    _updateLocalMessageStatus(messageId, 'failed');
    if (mounted) {
      setState(() {
        _activeQuoteMessageId = snapshot.quotedMessageId;
      });
    } else {
      _activeQuoteMessageId = snapshot.quotedMessageId;
    }
    await _persistMessageStatus(messageId, 'failed');
    if (snapshot.pendingAttachments.isNotEmpty) {
      await _cleanupRestoredComposerRetryState(messageId);
      await _trackRestoredMediaContinuation(
        snapshot: snapshot,
        messageId: messageId,
      );
    } else if (snapshot.draftText.isNotEmpty) {
      await _trackRestoredMediaContinuation(
        snapshot: snapshot,
        messageId: messageId,
      );
    } else {
      _clearRestoredMediaContinuationTracking();
    }
    if (showSnackBar && snackText != null) {
      _showFloatingSnackBar(snackText);
    }
  }

  Future<void> _applyProjectedGroupUploadFailureUi(
    ConversationComposerSnapshot snapshot, {
    required String messageId,
    required bool terminal,
  }) async {
    if (terminal) {
      _draftText = snapshot.draftText;
      _updateLocalMessageStatus(messageId, 'failed');
      if (mounted) {
        setState(() => _activeQuoteMessageId = snapshot.quotedMessageId);
        _updateComposerState(
          pendingAttachments: snapshot.pendingAttachments,
          isUploading: false,
        );
      } else {
        _activeQuoteMessageId = snapshot.quotedMessageId;
      }
      await _cleanupRestoredComposerRetryState(messageId);
      await _trackRestoredMediaContinuation(
        snapshot: snapshot,
        messageId: messageId,
      );
      return;
    }

    // Retryable upload failures remain owned by the durable outbox. The
    // composer and active quote stay cleared; the optimistic parent retains
    // its original quotedMessageId in storage.
    _updateLocalMessageStatus(messageId, 'queued_offline');
    if (mounted) {
      _updateComposerState(isUploading: false);
    }
  }

  Future<void> _restoreComposerSnapshotWithoutFailure(
    ConversationComposerSnapshot snapshot,
    String messageId, {
    String? snackText,
    bool showSnackBar = false,
  }) async {
    if (mounted) {
      setState(() {
        _draftText = snapshot.draftText;
        _activeQuoteMessageId = snapshot.quotedMessageId;
        _removeLocalMessage(messageId);
      });
      _updateComposerState(
        pendingAttachments: snapshot.pendingAttachments,
        isUploading: false,
      );
    }
    if (snapshot.pendingAttachments.isNotEmpty) {
      await _cleanupRestoredComposerRetryState(messageId);
    }
    _clearRestoredMediaContinuationTracking();
    try {
      await widget.msgRepo.deleteMessage(messageId);
    } catch (_) {}
    if (showSnackBar && snackText != null) {
      _showFloatingSnackBar(snackText);
    }
  }

  void _showFloatingSnackBar(String text, {Color? backgroundColor}) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// 210: persist the durable 'queued_offline' status for a message that could
  /// not send because WE are offline, and reflect it in the on-screen row.
  /// Unlike the failure helpers this deliberately does NOT restore the composer
  /// or mark the row 'failed' — the message stays durably queued and self-heals
  /// when connectivity returns (the stuck-sending recovery sweep re-drives it).
  /// The status write is the LAST write for this row, so it wins over the
  /// 'failed' the send use case stamped on the connectivity failure.
  Future<void> _markOutgoingMessageQueuedOffline(String messageId) async {
    // 210b guard: never regress a row that already settled — e.g. a self echo
    // reconciled it to 'sent' between the awaited send result and this write
    // (review 210b-F5). The queued stamp is only valid over in-flight or
    // failure states.
    final current = await widget.msgRepo.getMessage(messageId);
    if (current != null &&
        (current.status == 'sent' ||
            current.status == 'delivered' ||
            current.status == 'inboxed')) {
      return;
    }
    _updateLocalMessageStatus(messageId, GroupMessage.statusQueuedOffline);
    await _persistMessageStatus(messageId, GroupMessage.statusQueuedOffline);
  }

  /// 210/210b: the queued-send informational snackbar, mirroring the 1:1
  /// `conversation_wired` copy EXACTLY. The LANE is decided by the send-result
  /// custody contract (queuedOffline / the offline error fallback); relayReady
  /// only picks the COPY — the 192 lesson: while the phone still believes it
  /// is online (the 15-30s stale relay-state window after losing internet) a
  /// "back online" promise would be dishonest, so the queued-retry copy names
  /// what is actually happening. Slate/blueGrey floating surface
  /// (informational/self-healing tone, NOT error-red).
  void _showOfflineQueuedSnackBar() {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    final senderOfflineCopy = l10n.offline_send_promise;
    final queuedRetryCopy = l10n.offline_retry_delayed;
    final senderOffline = !widget.p2pService.currentState.relayReady;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              senderOffline
                  ? Icons.wifi_off_rounded
                  : Icons.schedule_send_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                senderOffline ? senderOfflineCopy : queuedRetryCopy,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.blueGrey[700],
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _refreshMessageWithHydratedMedia(
    String messageId, {
    List<MediaAttachment>? fallbackMedia,
  }) async {
    final refreshedMessage = await widget.msgRepo.getMessage(messageId);
    if (refreshedMessage == null || !mounted) return;
    final hydratedMedia = await _resolveHydratedMediaForMessage(
      messageId,
      ownerMessage: refreshedMessage,
      fallbackMedia: fallbackMedia,
    );
    if (!mounted) return;
    setState(() {
      _upsertMessage(refreshedMessage.copyWith(media: hydratedMedia));
      _updateMediaForMessage(messageId, hydratedMedia);
    });
  }

  Future<List<MediaAttachment>> _resolveHydratedMediaForMessage(
    String messageId, {
    GroupMessage? ownerMessage,
    List<MediaAttachment>? fallbackMedia,
  }) async {
    final mediaAttachmentRepo = widget.mediaAttachmentRepo;
    if (mediaAttachmentRepo == null) {
      return fallbackMedia ?? const <MediaAttachment>[];
    }

    final attachments = await mediaAttachmentRepo.getAttachmentsForMessage(
      messageId,
      owner: MediaOwnerLane.group,
    );
    if (attachments.isEmpty) {
      return fallbackMedia ?? const <MediaAttachment>[];
    }

    final message = ownerMessage ?? await widget.msgRepo.getMessage(messageId);
    return _resolveAttachmentsForDisplay(
      attachments,
      allowMissingEncryptionForLocalOutgoing: message?.isIncoming == false,
    );
  }

  Future<Map<String, List<MediaAttachment>>> _loadResolvedMediaMap(
    List<GroupMessage> messages,
  ) async {
    final mediaRepo = widget.mediaAttachmentRepo;
    if (mediaRepo == null || messages.isEmpty) {
      return {};
    }

    final rawMap = await mediaRepo.getAttachmentsForMessages(
      messages.map((m) => m.id).toList(),
      owner: MediaOwnerLane.group,
    );
    final messagesById = {for (final message in messages) message.id: message};
    final mediaMap = <String, List<MediaAttachment>>{};
    for (final entry in rawMap.entries) {
      mediaMap[entry.key] = await _resolveAttachmentsForDisplay(
        entry.value,
        allowMissingEncryptionForLocalOutgoing:
            messagesById[entry.key]?.isIncoming == false,
      );
    }
    return mediaMap;
  }

  Future<List<MediaAttachment>> _loadResolvedAttachmentsForMessage(
    String messageId,
  ) async {
    final mediaRepo = widget.mediaAttachmentRepo;
    if (mediaRepo == null) return const [];
    final attachments = await mediaRepo.getAttachmentsForMessage(
      messageId,
      owner: MediaOwnerLane.group,
    );
    final message = await widget.msgRepo.getMessage(messageId);
    return _resolveAttachmentsForDisplay(
      attachments,
      allowMissingEncryptionForLocalOutgoing: message?.isIncoming == false,
    );
  }

  Future<List<MediaAttachment>> _resolveAttachmentsForDisplay(
    List<MediaAttachment> attachments, {
    required bool allowMissingEncryptionForLocalOutgoing,
  }) async {
    final mediaFileManager = widget.mediaFileManager;
    if (mediaFileManager == null) {
      return Future.wait(
        attachments.map((attachment) async {
          if (attachment.downloadStatus == kMediaDownloadStatusDone &&
              !GroupMediaIntegrityPolicy.canDisplayVerifiedGroupMedia(
                attachment,
              )) {
            if (attachment.localPath == null &&
                _hasRecoverableVisibleGroupMedia(attachment)) {
              return _markDisplayPendingRecovery(attachment);
            }
            return _markDisplayIntegrityFailed(attachment);
          }
          return attachment;
        }),
      );
    }

    final resolved = <MediaAttachment>[];
    for (final attachment in attachments) {
      if (attachment.downloadStatus == kMediaDownloadStatusDone &&
          !GroupMediaIntegrityPolicy.hasValidContentHash(attachment)) {
        resolved.add(await _markDisplayIntegrityFailed(attachment));
        continue;
      }
      if (attachment.localPath == null) {
        if (attachment.downloadStatus == kMediaDownloadStatusDone) {
          if (_hasRecoverableVisibleGroupMedia(attachment)) {
            resolved.add(await _markDisplayPendingRecovery(attachment));
          } else {
            resolved.add(await _markDisplayIntegrityFailed(attachment));
          }
          continue;
        }
        resolved.add(attachment);
        continue;
      }
      final absolutePath = await mediaFileManager.resolveStoredPath(
        attachment.localPath!,
      );
      final isPendingUploadPath =
          _isPendingUploadPath(attachment.localPath!) ||
          _isPendingUploadPath(absolutePath);
      if (isPendingUploadPath) {
        if (attachment.downloadStatus == kMediaDownloadStatusDone &&
            !allowMissingEncryptionForLocalOutgoing &&
            !GroupMediaIntegrityPolicy.canDisplayVerifiedGroupMedia(
              attachment.copyWith(localPath: absolutePath),
            )) {
          resolved.add(await _markDisplayIntegrityFailed(attachment));
          continue;
        }
        resolved.add(attachment.copyWith(localPath: absolutePath));
        continue;
      }
      if (attachment.downloadStatus == kMediaDownloadStatusDone &&
          !GroupMediaIntegrityPolicy.canDisplayVerifiedGroupMedia(
            attachment.copyWith(localPath: absolutePath),
          )) {
        final allowsLocalOutgoingMissingEncryption =
            allowMissingEncryptionForLocalOutgoing &&
            !attachment.hasEncryptionMetadata &&
            GroupMediaIntegrityPolicy.hasValidContentHash(attachment) &&
            _isOwnedGroupMediaPath(attachment.localPath!, absolutePath);
        if (allowsLocalOutgoingMissingEncryption) {
          resolved.add(attachment.copyWith(localPath: absolutePath));
          continue;
        }
        resolved.add(await _markDisplayIntegrityFailed(attachment));
        continue;
      }
      final exists = await File(absolutePath).exists();
      if (!exists && attachment.downloadStatus == kMediaDownloadStatusDone) {
        final repaired = await _repairMissingDoneAttachmentFromLatestLocalPath(
          attachment: attachment,
          originalResolvedPath: absolutePath,
        );
        if (repaired != null) {
          resolved.add(repaired);
          continue;
        }
        final diagnostics = await _groupMediaDonePathDiagnostics(
          attachment: attachment,
          resolvedPath: absolutePath,
        );
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_MEDIA_DURABILITY_DONE_PATH_MISSING',
          details: {
            'attachmentId': attachment.id,
            'messageId': attachment.messageId,
            'groupId': widget.group.id,
            'mime': attachment.mime,
            'mediaType': attachment.mediaType,
            'storedPath': attachment.localPath,
            'resolvedPath': absolutePath,
            'storedPathKind': _groupMediaPathKind(attachment.localPath),
            'resolvedPathKind': _groupMediaPathKind(absolutePath),
            'expectedBytes': attachment.size,
            'hasContentHash': attachment.contentHash?.isNotEmpty == true,
            'hasEncryptionMetadata': attachment.hasEncryptionMetadata,
            'diagnostics': diagnostics,
            'nextStatus': kMediaDownloadStatusPending,
          },
        );
        try {
          await widget.mediaAttachmentRepo?.updateDownloadStatus(
            attachment.id,
            kMediaDownloadStatusPending,
          );
        } catch (_) {}
        resolved.add(
          attachment.copyWith(
            localPath: absolutePath,
            downloadStatus: kMediaDownloadStatusPending,
          ),
        );
        continue;
      }
      resolved.add(attachment.copyWith(localPath: absolutePath));
    }
    return resolved;
  }

  Future<MediaAttachment?> _repairMissingDoneAttachmentFromLatestLocalPath({
    required MediaAttachment attachment,
    required String originalResolvedPath,
  }) async {
    final mediaAttachmentRepo = widget.mediaAttachmentRepo;
    final mediaFileManager = widget.mediaFileManager;
    if (mediaAttachmentRepo == null || mediaFileManager == null) {
      return null;
    }

    final canonicalRelativePath = mediaFileManager.relativePathForAttachment(
      contactPeerId: widget.group.id,
      blobId: attachment.id,
      mime: attachment.mime,
    );
    final candidates = <MediaAttachment>[];
    try {
      final latest = await mediaAttachmentRepo.getAttachmentsForMessage(
        attachment.messageId,
        owner: MediaOwnerLane.group,
      );
      candidates.addAll(
        latest.where((candidate) => candidate.id == attachment.id),
      );
    } catch (_) {}
    candidates.add(attachment.copyWith(localPath: canonicalRelativePath));

    final seenResolvedPaths = <String>{};
    for (final candidate in candidates) {
      final storedPath = candidate.localPath;
      if (storedPath == null || storedPath.isEmpty) {
        continue;
      }
      late final String candidateResolvedPath;
      try {
        candidateResolvedPath = await mediaFileManager.resolveStoredPath(
          storedPath,
        );
      } catch (_) {
        continue;
      }
      if (!seenResolvedPaths.add(candidateResolvedPath)) {
        continue;
      }
      final file = File(candidateResolvedPath);
      if (!await file.exists()) {
        continue;
      }

      final repairStoredPath =
          _isOwnedGroupMediaPath(canonicalRelativePath, candidateResolvedPath)
          ? canonicalRelativePath
          : storedPath;
      try {
        await mediaAttachmentRepo.updateLocalPath(
          attachment.id,
          repairStoredPath,
        );
      } catch (_) {}
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_MEDIA_DURABILITY_DONE_PATH_REPAIRED',
        details: {
          'attachmentId': attachment.id,
          'messageId': attachment.messageId,
          'groupId': widget.group.id,
          'mime': attachment.mime,
          'mediaType': attachment.mediaType,
          'originalStoredPath': attachment.localPath,
          'originalResolvedPath': originalResolvedPath,
          'repairStoredPath': repairStoredPath,
          'repairResolvedPath': candidateResolvedPath,
          'repairStoredPathKind': _groupMediaPathKind(repairStoredPath),
          'repairResolvedPathKind': _groupMediaPathKind(candidateResolvedPath),
          'candidateStatus': candidate.downloadStatus,
          'fileBytes': await file.length(),
        },
      );
      return candidate.copyWith(
        localPath: candidateResolvedPath,
        downloadStatus: kMediaDownloadStatusDone,
      );
    }

    return null;
  }

  Future<Map<String, Object?>> _groupMediaDonePathDiagnostics({
    required MediaAttachment attachment,
    required String resolvedPath,
  }) async {
    final mediaFileManager = widget.mediaFileManager;
    final diagnostics = <String, Object?>{
      'primaryPath': await _groupMediaPathProbe(resolvedPath),
    };
    if (mediaFileManager == null) {
      return diagnostics;
    }

    final canonicalRelativePath = mediaFileManager.relativePathForAttachment(
      contactPeerId: widget.group.id,
      blobId: attachment.id,
      mime: attachment.mime,
    );
    final canonicalResolvedPath = await mediaFileManager.resolveStoredPath(
      canonicalRelativePath,
    );
    diagnostics['canonicalPath'] = await _groupMediaPathProbe(
      canonicalResolvedPath,
      storedPath: canonicalRelativePath,
    );
    diagnostics['encryptedCompanionPath'] = await _groupMediaPathProbe(
      '$canonicalResolvedPath.enc',
      storedPath: '$canonicalRelativePath.enc',
    );

    try {
      final latest = await widget.mediaAttachmentRepo?.getAttachmentsForMessage(
        attachment.messageId,
        owner: MediaOwnerLane.group,
      );
      final latestAttachment = latest
          ?.where((candidate) => candidate.id == attachment.id)
          .firstOrNull;
      if (latestAttachment != null) {
        diagnostics['latestRow'] = {
          'downloadStatus': latestAttachment.downloadStatus,
          'storedPath': latestAttachment.localPath,
          'storedPathKind': _groupMediaPathKind(latestAttachment.localPath),
          'hasLocalPath':
              latestAttachment.localPath != null &&
              latestAttachment.localPath!.isNotEmpty,
          'hasContentHash': latestAttachment.contentHash?.isNotEmpty == true,
          'hasEncryptionMetadata': latestAttachment.hasEncryptionMetadata,
        };
      }
    } catch (e) {
      diagnostics['latestRowError'] = e.toString();
    }

    return diagnostics;
  }

  Future<Map<String, Object?>> _groupMediaPathProbe(
    String path, {
    String? storedPath,
  }) async {
    final storedPathKind = storedPath == null
        ? null
        : _groupMediaPathKind(storedPath);
    final details = <String, Object?>{
      'storedPath': ?storedPath,
      'storedPathKind': ?storedPathKind,
      'resolvedPath': path,
      'resolvedPathKind': _groupMediaPathKind(path),
    };
    try {
      final file = File(path);
      final exists = await file.exists();
      details['fileExists'] = exists;
      if (exists) {
        details['fileBytes'] = await file.length();
      }
    } catch (e) {
      details['statError'] = e.toString();
    }
    return details;
  }

  String _groupMediaPathKind(String? path) {
    if (path == null || path.isEmpty) {
      return 'empty';
    }
    if (path.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path)) {
      return 'absolute';
    }
    return 'relative';
  }

  bool _isOwnedGroupMediaPath(String storedPath, String absolutePath) {
    bool matches(String path) {
      final normalized = path.replaceAll('\\', '/');
      final mediaPrefix = 'media/${widget.group.id}/';
      final pendingPrefix = 'pending_uploads/';
      return normalized.startsWith(mediaPrefix) ||
          normalized.contains('/$mediaPrefix') ||
          normalized.startsWith(pendingPrefix) ||
          normalized.contains('/$pendingPrefix');
    }

    return matches(storedPath) || matches(absolutePath);
  }

  Future<MediaAttachment> _markDisplayIntegrityFailed(
    MediaAttachment attachment, {
    String? absolutePath,
    bool deleteLocalFile = false,
  }) async {
    try {
      await widget.mediaAttachmentRepo?.updateDownloadStatus(
        attachment.id,
        kMediaDownloadStatusIntegrityFailed,
      );
    } catch (_) {}

    if (deleteLocalFile && absolutePath != null) {
      await _deleteUnsafeLocalMediaFile(
        attachment.copyWith(localPath: absolutePath),
      );
    }

    final quarantined = attachment.copyWith(
      clearLocalPath: true,
      downloadStatus: kMediaDownloadStatusIntegrityFailed,
    );
    try {
      await widget.mediaAttachmentRepo?.saveAttachment(
        quarantined,
        owner: MediaOwnerLane.group,
      );
    } catch (_) {}

    return quarantined;
  }

  Future<MediaAttachment> _markDisplayPendingRecovery(
    MediaAttachment attachment,
  ) async {
    final pending = attachment.copyWith(
      clearLocalPath: true,
      downloadStatus: kMediaDownloadStatusPending,
    );
    try {
      await widget.mediaAttachmentRepo?.saveAttachment(
        pending,
        owner: MediaOwnerLane.group,
      );
    } catch (_) {}
    return pending;
  }

  bool _shouldRecoverVisibleAttachment(MediaAttachment attachment) {
    final statusIsRecoverable =
        attachment.downloadStatus == kMediaDownloadStatusPending ||
        attachment.downloadStatus == kMediaDownloadStatusDownloading ||
        // A transient `failed` row is recoverable only while under the bounded
        // retry budget; the terminal `download_failed` is never re-recovered
        // (INV-DL-1) — isRetryableDownloadFailure encodes both rules.
        GroupMediaIntegrityPolicy.isRetryableDownloadFailure(attachment);
    return statusIsRecoverable && _hasRecoverableVisibleGroupMedia(attachment);
  }

  bool _hasRecoverableVisibleGroupMedia(MediaAttachment attachment) {
    return GroupMediaMimePolicy.validateDescriptor(
          mime: attachment.mime,
          mediaType: attachment.mediaType,
        ).isValid &&
        // Recovery eligibility: permissive cross-type backstop, not per-type
        // SEND caps — never refuse to recover already-received media that is
        // within the cross-type maximum.
        GroupMediaSizePolicy.validateAttachments([
          attachment,
        ], perMediaLimitBytes: kGroupMediaPerAttachmentLimitBytes).isValid &&
        GroupMediaIntegrityPolicy.hasRequiredVerificationMetadata(attachment);
  }

  bool _isPendingUploadPath(String path) {
    return path.contains('pending_uploads/') ||
        path.contains('pending_uploads\\');
  }

  Future<void> _applyMessageUpdate(
    GroupMessage message, {
    bool markAsRead = true,
  }) async {
    final updateGroupId = message.groupId;
    if (widget.group.id != updateGroupId ||
        _group.id != updateGroupId ||
        _locallyRemovedMessageIds.contains(message.id)) {
      return;
    }
    final latestMessage =
        await widget.msgRepo.getMessage(message.id) ?? message;
    if (!mounted ||
        widget.group.id != updateGroupId ||
        _group.id != updateGroupId ||
        latestMessage.groupId != updateGroupId ||
        _locallyRemovedMessageIds.contains(message.id)) {
      return;
    }

    // 157 follow-up (TC-159-11, mirror of 156 QW-9): skip the per-message
    // attachment DB read ONLY for a PURE text/status update to an already-shown
    // message with no media on either side (the common sent→delivered→read
    // flip). Unlike the 1:1 screen — where media enrichment of a visible message
    // flows through a SEPARATE _recoverVisibleMedia path — the group's media
    // recovery (background download complete, integrity recovery) flows through
    // THIS path, so any message that has media (carried on the event OR already
    // shown in _mediaMap) MUST still re-resolve, or a recovered image would
    // never refresh.
    final alreadyShown = _messages.any((m) => m.id == latestMessage.id);
    final shownMedia = _mediaMap[latestMessage.id] ?? const <MediaAttachment>[];
    final shouldResolveMedia =
        !alreadyShown || message.media.isNotEmpty || shownMedia.isNotEmpty;
    final media = shouldResolveMedia
        ? await _loadResolvedAttachmentsForMessage(latestMessage.id)
        : shownMedia;
    if (!mounted ||
        widget.group.id != updateGroupId ||
        _group.id != updateGroupId ||
        _locallyRemovedMessageIds.contains(message.id)) {
      return;
    }

    // 159: queue for the per-frame flush instead of a direct per-event setState.
    _enqueueGroupMessageUpdate(
      latestMessage,
      media: media,
      markAsRead: markAsRead,
    );
  }

  /// 159: apply a resolved group message update to [_messages]/[_mediaMap]
  /// SYNCHRONOUSLY (preserving its ordering with other synchronous mutations,
  /// e.g. an optimistic send / cancel), but defer the expensive REORDER +
  /// setState + the scroll-capture/restore + markAsRead to ONE per-frame flush.
  void _enqueueGroupMessageUpdate(
    GroupMessage message, {
    required List<MediaAttachment> media,
    required bool markAsRead,
  }) {
    if (message.groupId != widget.group.id ||
        message.groupId != _group.id ||
        _locallyRemovedMessageIds.contains(message.id)) {
      return;
    }
    _upsertIntoGroupMessagesUnsorted(message);
    _updateMediaForMessage(message.id, media);
    _groupNeedsFlush = true;
    if (markAsRead) _groupWantsMarkRead = true;
    // The per-message media recovery is an independent side effect (no batching
    // needed) — fire it as the message lands.
    if (media.any(_shouldRecoverVisibleAttachment)) {
      unawaited(_downloadPendingMedia({message.id: media}));
    }
    if (!_groupFlushScheduled) {
      _groupFlushScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _flushGroupMessageUpdates(),
      );
      // 158: the chat surface suppresses its ambient idle-glow, so an otherwise
      // idle conversation schedules no frames, and addPostFrameCallback does NOT
      // request one. Explicitly schedule a frame so the deferred flush runs.
      WidgetsBinding.instance.scheduleFrame();
    }
  }

  /// 159: id-keyed upsert into [_messages] WITHOUT reordering — the reorder is
  /// coalesced to [_flushGroupMessageUpdates].
  void _upsertIntoGroupMessagesUnsorted(GroupMessage message) {
    final index = _messages.indexWhere((m) => m.id == message.id);
    if (index >= 0) {
      final updated = List<GroupMessage>.from(_messages);
      updated[index] = message;
      _messages = updated;
    } else {
      _messages = [..._messages, message];
    }
  }

  /// 159: the per-frame flush — reorder + cap the coalesced upserts ONCE in ONE
  /// setState, with the scroll-offset capture/restore + markAsRead run exactly
  /// once against the post-batch state (one capture before, one restore after).
  void _flushGroupMessageUpdates() {
    _groupFlushScheduled = false;
    final needsFlush = _groupNeedsFlush;
    final wantMarkRead = _groupWantsMarkRead;
    _groupNeedsFlush = false;
    _groupWantsMarkRead = false;
    if (!mounted || !needsFlush) return;

    // Capture the scroll position ONCE before the batched reorder. No setState
    // ran since the synchronous upserts, so this is the genuine pre-burst offset.
    final preserveScrollOffset = _shouldPreserveScrollOffset();
    final previousOffset = _scrollController.hasClients
        ? _scrollController.position.pixels
        : 0.0;

    setState(() {
      GroupConversationWired.debugReorderInvocationCount++;
      _messages = trimToNewestInMemoryCap(
        orderGroupMessagesForTimeline(_messages),
      );
    });

    // Restore the scroll offset ONCE after the whole batch.
    _restoreScrollAfterMessageUpdate(
      preserveScrollOffset: preserveScrollOffset,
      previousOffset: previousOffset,
    );

    if (wantMarkRead) {
      unawaited(_markVisibleReadIfAllowed());
    }
  }

  // -------------------------------------------------------------------------
  // Attachment picker
  // -------------------------------------------------------------------------

  void _onAttach() {
    if (!_canWrite) return;
    final readableColors = context.backgroundReadableColors;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: readableColors.surfaceBase,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        side: BorderSide(color: readableColors.divider),
      ),
      builder: (ctx) {
        final sheetColors = ctx.backgroundReadableColors;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: sheetColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: Icon(
                  Icons.photo_library,
                  color: sheetColors.iconPrimary,
                ),
                title: Text(
                  AppLocalizations.of(context)!.picker_media_library,
                  style: TextStyle(color: sheetColors.textPrimary),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickFromGallery();
                },
              ),
              ListTile(
                leading: Icon(Icons.camera_alt, color: sheetColors.iconPrimary),
                title: Text(
                  AppLocalizations.of(context)!.picker_take_photo,
                  style: TextStyle(color: sheetColors.textPrimary),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickFromCamera();
                },
              ),
              ListTile(
                leading: Icon(Icons.videocam, color: sheetColors.iconPrimary),
                title: Text(
                  AppLocalizations.of(context)!.picker_record_video,
                  style: TextStyle(color: sheetColors.textPrimary),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickVideoFromCamera();
                },
              ),
              // 204 (BUG-1): explicit Cancel to go back to the chat. Dismisses
              // the sheet ONLY — never picks, never touches staged media.
              ListTile(
                key: GroupConversationWired.attachSheetCancelKey,
                leading: Icon(
                  Icons.close_rounded,
                  color: sheetColors.iconPrimary,
                ),
                title: Text(
                  AppLocalizations.of(context)!.btn_cancel,
                  style: TextStyle(color: sheetColors.textPrimary),
                ),
                onTap: () => Navigator.pop(ctx),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickFromGallery() async {
    try {
      final remaining =
          _maxAttachments - _composerController.pendingAttachments.length;
      if (remaining <= 0) return;
      final picked = await _mediaPicker.pickMultipleMedia();
      if (picked.isEmpty || !mounted) return;
      final selectedFiles = picked.take(remaining).toList();
      final processor = widget.imageProcessor;
      final processingTotal = selectedFiles
          .where((xf) => processor?.isProcessableVideo(xf.path) ?? false)
          .length;
      final useBatchProcessing = processingTotal > 1;
      var processingCurrent = 0;
      var didStartBatchProcessing = false;
      final media = <PendingComposerMedia>[];
      try {
        for (final xf in selectedFiles) {
          final isProcessableVideo =
              processor?.isProcessableVideo(xf.path) ?? false;
          if (useBatchProcessing && isProcessableVideo) {
            didStartBatchProcessing = true;
            processingCurrent++;
            _updateComposerState(
              isProcessing: true,
              processingProgress: 0.0,
              processingCurrent: processingCurrent,
              processingTotal: processingTotal,
            );
          }
          try {
            final result = await _preparePendingMedia(
              xf.path,
              ownsProcessingLifecycle: !useBatchProcessing,
            );
            media.add(result);
          } on _RejectedPendingGroupMediaException {
            continue;
          }
        }
      } finally {
        if (useBatchProcessing && didStartBatchProcessing && mounted) {
          _updateComposerState(
            isProcessing: false,
            processingProgress: 0.0,
            processingCurrent: 0,
            processingTotal: 0,
          );
        }
      }
      if (!mounted) return;
      await _attemptAddPendingMedia(media);
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_CONV_FL_PICK_GALLERY_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _pickFromCamera() async {
    try {
      final picked = await _mediaPicker.pickImage(source: ImageSource.camera);
      if (picked == null || !mounted) return;
      if (_composerController.pendingAttachments.length >= _maxAttachments) {
        return;
      }
      final result = await _preparePendingMedia(picked.path);
      if (!mounted) return;
      await _attemptAddPendingMedia([result]);
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_CONV_FL_PICK_CAMERA_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _pickVideoFromCamera() async {
    try {
      final picked = await _mediaPicker.pickVideo(source: ImageSource.camera);
      if (picked == null || !mounted) return;
      if (_composerController.pendingAttachments.length >= _maxAttachments) {
        return;
      }
      final result = await _preparePendingMedia(picked.path);
      if (!mounted) return;
      await _attemptAddPendingMedia([result]);
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_CONV_FL_PICK_VIDEO_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  void _removeAttachment(int index) {
    if (!_canWrite) return;
    if (index < 0 || index >= _composerController.pendingAttachments.length) {
      return;
    }
    final updated = List<PendingComposerMedia>.from(
      _composerController.pendingAttachments,
    );
    updated.removeAt(index);
    _clearRestoredMediaContinuationTracking();
    _updateComposerState(pendingAttachments: updated);
  }

  void _upsertMessage(GroupMessage message) {
    _recordMessageMutation(message.id);
    GroupConversationWired.debugReorderInvocationCount++;
    final updated = List<GroupMessage>.from(_messages);
    final index = updated.indexWhere((existing) => existing.id == message.id);
    if (index >= 0) {
      updated[index] = message;
    } else {
      updated.add(message);
    }
    // 159 (rebuild-storms-3): cap the live-append window newest-first. The group
    // has no incremental older-page pagination, so the self-heal for an evicted
    // row is a full `_loadMessages` re-fetch (no flag to set).
    _messages = trimToNewestInMemoryCap(orderGroupMessagesForTimeline(updated));
  }

  void _updateMediaForMessage(
    String messageId,
    List<MediaAttachment> attachments,
  ) {
    _recordMessageMutation(messageId);
    final next = Map<String, List<MediaAttachment>>.from(_mediaMap);
    if (attachments.isEmpty) {
      next.remove(messageId);
    } else {
      next[messageId] = attachments;
    }
    _mediaMap = next;
  }

  void _updateLocalMessageStatus(String messageId, String status) {
    final idx = _messages.indexWhere((m) => m.id == messageId);
    if (idx < 0) return;
    _recordMessageMutation(messageId);
    final updated = List<GroupMessage>.from(_messages);
    updated[idx] = updated[idx].copyWith(status: status);
    if (mounted) {
      setState(() => _messages = updated);
    } else {
      _messages = updated;
    }
  }

  void _removeLocalMessage(String messageId) {
    _recordMessageMutation(messageId);
    _locallyRemovedMessageIds.add(messageId);
    final removesActiveAnchorTarget =
        _activeSharedMediaAnchorTargetId == messageId;
    final invalidatesAnchorReplay =
        removesActiveAnchorTarget ||
        _activeSharedMediaAnchorInjectedIds.contains(messageId) ||
        _sharedMediaAnchorReplayWindow.any(
          (message) => message.id == messageId,
        );
    final messageIdsToRemove = <String>{messageId};
    if (removesActiveAnchorTarget) {
      messageIdsToRemove.addAll(_activeSharedMediaAnchorInjectedIds);
    }
    final nextMessages = _messages
        .where((message) => !messageIdsToRemove.contains(message.id))
        .toList();
    final nextMedia = Map<String, List<MediaAttachment>>.from(_mediaMap);
    for (final removedId in messageIdsToRemove) {
      nextMedia.remove(removedId);
    }
    void applyRemoval() {
      _messages = nextMessages;
      _mediaMap = nextMedia;
      if (removesActiveAnchorTarget) {
        if (_highlightedMessageId == messageId) {
          _highlightedMessageId = null;
          _highlightScrollResolved = false;
        }
        _activeSharedMediaAnchorGroupId = null;
        _activeSharedMediaAnchorTargetId = null;
        _activeSharedMediaAnchorInjectedIds = const <String>{};
      } else if (_activeSharedMediaAnchorInjectedIds.contains(messageId)) {
        _activeSharedMediaAnchorInjectedIds = <String>{
          ..._activeSharedMediaAnchorInjectedIds,
        }..remove(messageId);
      }
      if (invalidatesAnchorReplay) {
        // A local delete/tombstone is newer authority than a captured anchor
        // snapshot. Never let a late page replay resurrect that row.
        _invalidateSharedMediaAnchorReplay();
      }
    }

    if (mounted) {
      setState(applyRemoval);
    } else {
      applyRemoval();
    }
  }

  Future<void> _persistMessageStatus(String messageId, String status) async {
    try {
      await widget.msgRepo.updateMessageStatus(messageId, status);
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_CONV_FL_STATUS_UPDATE_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  void _updateComposerState({
    List<PendingComposerMedia>? pendingAttachments,
    Set<int>? invalidAttachmentIndices,
    Map<int, String>? invalidAttachmentReasons,
    bool? isUploading,
    bool? isProcessing,
    double? processingProgress,
    int? processingCurrent,
    int? processingTotal,
    VoiceRecordingState? recordingState,
    Duration? recordingDuration,
    List<double>? amplitudeValues,
  }) {
    final current = _composerController.value;
    final effectivePendingAttachments =
        pendingAttachments ?? _composerController.pendingAttachments;
    final pendingAttachmentFiles = pendingAttachments == null
        ? null
        : effectivePendingAttachments
              .map((attachment) => attachment.file)
              .toList(growable: false);
    // 149: re-derive the size/GIF reject set from the LIVE pending list whenever
    // the attachment list changes (pick/remove), so the inline reject-chip +
    // Send-disable always track the current attachments. Size/GIF only — the
    // unsupported-MIME hard reject stays a SEND-time snackbar, not a chip.
    var nextInvalidIndices = invalidAttachmentIndices;
    var nextInvalidReasons = invalidAttachmentReasons;
    bool? nextHasTotalSizeOverflow;
    if (pendingAttachments != null && invalidAttachmentIndices == null) {
      if (effectivePendingAttachments.isEmpty) {
        nextInvalidIndices = const <int>{};
        nextInvalidReasons = const <int, String>{};
        nextHasTotalSizeOverflow = false;
      } else {
        final rejections = collectPendingMediaSizeRejections(
          effectivePendingAttachments,
          _mimeFromPath,
        );
        nextInvalidIndices = rejections.map((r) => r.index).toSet();
        nextInvalidReasons = {
          for (final rejection in rejections) rejection.index: rejection.reason,
        };
        // 149: individually-valid attachments whose summed bytes exceed the
        // total message budget get a strip-level note (there is no per-chip
        // index to mark). Suppressed when any attachment is over its own cap —
        // that per-chip reject already disables Send, so the two never double up.
        nextHasTotalSizeOverflow =
            nextInvalidIndices.isEmpty &&
            pendingMediaTotalSizeOverflow(effectivePendingAttachments);
      }
    }
    final next = current.copyWith(
      pendingAttachments: pendingAttachmentFiles,
      invalidAttachmentIndices: nextInvalidIndices,
      invalidAttachmentReasons: nextInvalidReasons,
      hasTotalSizeOverflow: nextHasTotalSizeOverflow,
      isUploading: isUploading,
      isProcessing: isProcessing,
      processingProgress: processingProgress,
      processingCurrent: processingCurrent,
      processingTotal: processingTotal,
      recordingState: recordingState,
      recordingDuration: recordingDuration,
      amplitudeValues: amplitudeValues,
    );
    _composerController.publish(
      state: next,
      pendingAttachments: pendingAttachments,
    );
  }

  bool _shouldPreserveScrollOffset() {
    if (!_scrollController.hasClients) return false;
    return _scrollController.position.pixels > _liveEdgeTolerance;
  }

  void _restoreScrollAfterMessageUpdate({
    required bool preserveScrollOffset,
    required double previousOffset,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      if (!preserveScrollOffset) {
        _scrollController.jumpTo(0);
        return;
      }

      final maxExtent = _scrollController.position.maxScrollExtent;
      final targetOffset = previousOffset.clamp(0.0, maxExtent).toDouble();
      _scrollController.jumpTo(targetOffset);
    });
  }

  /// Snaps the reversed timeline back to the live edge (offset 0, newest).
  /// Used for *own* sends: the user just acted, so there is no "reading
  /// history" ambiguity — land them on their own message.
  void _scrollToLiveEdge() {
    _restoreScrollAfterMessageUpdate(
      preserveScrollOffset: false,
      previousOffset: 0,
    );
  }

  /// Brings the notification-tapped message on-screen when the conversation is
  /// opened from a notification anchor. Best-effort and bounded: if the id is
  /// not in the loaded page yet, a later [_loadMessages] retries; once resolved
  /// it never re-fights a user who scrolls away.
  void _scrollToHighlightedMessage() {
    final targetId = _highlightedMessageId;
    if (targetId == null || _highlightScrollResolved) return;
    final chronologicalIndex = _messages.indexWhere((m) => m.id == targetId);
    if (chronologicalIndex < 0) {
      // Not in the loaded page yet — retried from the next _loadMessages.
      return;
    }
    _highlightScrollResolved = true;
    _bringHighlightOnScreen(chronologicalIndex, attempt: 0);
  }

  void _bringHighlightOnScreen(int chronologicalIndex, {required int attempt}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;

      final anchorContext = _highlightAnchorKey.currentContext;
      if (anchorContext != null) {
        // Row is built: precisely centre it (and stop — never re-fight scroll).
        Scrollable.ensureVisible(
          anchorContext,
          alignment: 0.5,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
        );
        return;
      }

      if (attempt >= _maxHighlightScrollRetries) return;

      // Row not built yet (lazy reversed list): coarse-jump toward its
      // estimated offset so it materialises, then retry. Re-reading the extent
      // each attempt lets the estimate converge as more rows lay out.
      final count = _messages.length;
      final reversedIndex = count - 1 - chronologicalIndex;
      final maxExtent = _scrollController.position.maxScrollExtent;
      final viewport = _scrollController.position.viewportDimension;
      final estimate = count <= 1
          ? 0.0
          : (reversedIndex / (count - 1)) * maxExtent - viewport / 2;
      _scrollController.jumpTo(estimate.clamp(0.0, maxExtent).toDouble());

      _bringHighlightOnScreen(chronologicalIndex, attempt: attempt + 1);
    });
  }

  // -------------------------------------------------------------------------
  // Voice recording
  // -------------------------------------------------------------------------

  Future<void> _onRecordStart() async {
    if (!_canWrite) return;
    if (!await _refreshSendCapabilityAndCanWrite()) return;
    if (_isSending) return;
    final recorder = widget.audioRecorderService;
    if (recorder == null || _voiceCaptureController.state.isActive) {
      return;
    }

    final result = await _voiceCaptureController.start(
      recorder: recorder,
      requestPermission: widget.micPermissionGateway.request,
    );
    if (!mounted ||
        result.scopeGeneration != _voiceCaptureController.scopeGeneration) {
      return;
    }

    if (result.status == ConversationVoiceCaptureStartStatus.permissionDenied) {
      // permanentlyDenied = the OS will no longer re-prompt in-app, so the
      // recovery remains the lane-owned Settings deep-link (152).
      if (result.permissionStatus == MicPermissionStatus.permanentlyDenied) {
        await showMicPermissionDeniedPrompt(
          context,
          gateway: widget.micPermissionGateway,
        );
      }
      return;
    }
    if (result.status == ConversationVoiceCaptureStartStatus.failed) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_CONV_FL_RECORD_START_ERROR',
        details: {'error': result.error.toString()},
      );
    }
  }

  Future<void> _onRecordStop() async {
    if (!_canWrite) return;
    final mediaAttachmentRepo = widget.mediaAttachmentRepo;
    final mediaFileManager = widget.mediaFileManager;
    if (mediaAttachmentRepo == null ||
        mediaFileManager == null ||
        !_voiceCaptureController.state.isActive) {
      return;
    }
    final voiceLane = _ownPeerId == null ? null : _captureSendLane();

    if (_voiceCaptureController.state.phase ==
        ConversationVoiceCapturePhase.arming) {
      await _voiceCaptureController.stop();
      return;
    }
    if (!_tryBeginSendFlow()) return;
    MediaUploadLease? voiceUploadLease;

    try {
      final quotedMessageId = _activeQuoteMessageId;
      final outcome = await _voiceCaptureController.stop();
      if (outcome == null ||
          !_voiceCaptureController.isCurrentOutcome(outcome)) {
        return;
      }
      if (outcome.error != null) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_CONV_FL_RECORD_STOP_ERROR',
          details: {'error': outcome.error.toString()},
        );
        return;
      }

      final recording = outcome.recording;
      final waveform = outcome.waveform;
      if (recording == null ||
          voiceLane == null ||
          !_isCurrentVoiceSendLane(voiceLane, outcome)) {
        return;
      }

      final preflightMembers = await voiceLane.groupRepository.getMembers(
        voiceLane.groupId,
      );
      if (!_isCurrentVoiceSendLane(voiceLane, outcome)) return;
      if (!_passesGroupMediaAclPreflight(preflightMembers, surface: 'voice')) {
        return;
      }

      if (quotedMessageId != null && mounted) {
        setState(() => _activeQuoteMessageId = null);
      }

      final voiceContinuation =
          await _resolveRestoredVoiceContinuationForRecordStop(
            quotedMessageId: quotedMessageId,
            lane: voiceLane,
          );
      if (!_isCurrentVoiceSendLane(voiceLane, outcome)) return;
      final messageId = voiceContinuation?.messageId ?? _uuid.v4();
      final attachmentId = _uuid.v4();
      final now = voiceContinuation?.timestamp ?? DateTime.now().toUtc();
      voiceUploadLease = mediaUploadInFlightTracker.tryClaimAll([
        attachmentId,
      ], source: MediaUploadTriggerSource.foreground);
      if (voiceUploadLease == null) {
        _restoreActiveQuoteIfNeeded(quotedMessageId);
        return;
      }
      final optimisticMessage = GroupMessage(
        id: messageId,
        groupId: voiceLane.groupId,
        senderPeerId: voiceLane.senderPeerId,
        senderUsername: voiceLane.senderUsername,
        text: '',
        timestamp: now,
        quotedMessageId: quotedMessageId,
        // 210: same offline-first clock as the text path (voice is a separate
        // send surface).
        status: voiceLane.p2pService.currentState.relayReady
            ? 'sending'
            : GroupMessage.statusQueuedOffline,
        isIncoming: false,
        createdAt: now,
      );

      String? durableRelativePath;
      String? absoluteDurablePath;
      MediaAttachment? pendingAttachment;

      try {
        final validation = await GroupMediaMimePolicy.validateFile(
          path: recording.filePath,
          mime: recording.mime,
          mediaType: 'audio',
        );
        if (!mounted || !_isCurrentVoiceSendLane(voiceLane, outcome)) return;
        if (!validation.isValid) {
          emitFlowEvent(
            layer: 'FL',
            event: 'GROUP_CONV_FL_VOICE_REJECTED_INVALID_MIME',
            details: {'mime': recording.mime, 'reason': validation.reason},
          );
          throw const _RejectedPendingGroupMediaException();
        }
        final sizeValidation = GroupMediaSizePolicy.validateSize(
          sizeBytes: recording.sizeBytes,
          mime: recording.mime,
        );
        if (!sizeValidation.isValid) {
          emitFlowEvent(
            layer: 'FL',
            event: 'GROUP_CONV_FL_VOICE_REJECTED_INVALID_SIZE',
            details: {
              'mime': recording.mime,
              'sizeBytes': recording.sizeBytes,
              'reason': sizeValidation.reason,
            },
          );
          throw const _RejectedPendingGroupMediaException();
        }
        durableRelativePath = await mediaFileManager.copyToDurableStorage(
          sourceFilePath: recording.filePath,
          messageId: messageId,
          attachmentId: attachmentId,
          mime: recording.mime,
        );
        if (!_isCurrentVoiceSendLane(voiceLane, outcome)) {
          try {
            await mediaFileManager.deletePendingUploadDir(messageId);
          } catch (_) {}
          return;
        }
        absoluteDurablePath = await mediaFileManager.resolveStoredPath(
          durableRelativePath,
        );
        if (!_isCurrentVoiceSendLane(voiceLane, outcome)) {
          try {
            await mediaFileManager.deletePendingUploadDir(messageId);
          } catch (_) {}
          return;
        }
        final contentHash =
            await GroupMediaIntegrityPolicy.computeFileSha256Hex(
              absoluteDurablePath,
            );
        if (!_isCurrentVoiceSendLane(voiceLane, outcome)) {
          try {
            await mediaFileManager.deletePendingUploadDir(messageId);
          } catch (_) {}
          return;
        }
        try {
          await File(recording.filePath).delete();
        } catch (_) {}

        pendingAttachment = MediaAttachment(
          id: attachmentId,
          messageId: messageId,
          mime: recording.mime,
          size: recording.sizeBytes,
          mediaType: 'audio',
          durationMs: recording.durationMs,
          localPath: durableRelativePath,
          waveform: waveform,
          downloadStatus: 'upload_pending',
          createdAt: now.toIso8601String(),
          uploadRetryCount: 0,
          downloadRetryCount: 0,
          contentHash: contentHash,
          ownerLane: MediaOwnerLane.group,
        );
        // Attachment persistence and restored-row replacement are owned by the
        // bounded upload leaf below. The exact parent must exist first.
        await voiceLane.messageRepository.saveMessage(optimisticMessage);
        if (!_isCurrentVoiceSendLane(voiceLane, outcome)) return;
      } catch (e) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_CONV_FL_VOICE_DURABLE_PREP_ERROR',
          details: {'error': e.toString()},
        );
        if (voiceContinuation == null) {
          await _cleanupUnsentVoiceArtifacts(
            messageId: messageId,
            mediaAttachmentRepo: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
            messageRepository: voiceLane.messageRepository,
          );
        } else {
          _restoredVoiceContinuation = voiceContinuation;
        }
        if (mounted) {
          _updateComposerState(isUploading: false);
        }
        _restoreActiveQuoteIfNeeded(quotedMessageId);
        return;
      }

      final durablePendingAttachment = pendingAttachment;
      final durableAbsolutePath = absoluteDurablePath;
      final optimisticMedia = [
        durablePendingAttachment.copyWith(localPath: durableAbsolutePath),
      ];

      if (mounted) {
        setState(() {
          _upsertMessage(optimisticMessage);
          _updateMediaForMessage(messageId, optimisticMedia);
        });
        _scrollToLiveEdge();
      }

      final bgTaskId = await _beginBackgroundTaskGuarded(
        bridge: voiceLane.bridge,
      );
      ConversationUploadOperation<ConversationComposerSnapshot>? voiceOperation;
      try {
        // The native begin call may finish after route disposal. The durable
        // pending row is already committed, so leave recovery to the shared
        // retry coordinator without touching the disposed composer notifier.
        if (!mounted || !_isCurrentVoiceSendLane(voiceLane, outcome)) return;
        _updateComposerState(isUploading: true);
        voiceOperation = await _startRelayUploadTracking(recording.sizeBytes);
        _markRelayUploadStarted(voiceOperation, attachmentId);
        ForegroundGroupUploadLeafResult? voiceUpload;
        try {
          voiceUpload = await _runForegroundGroupUploadLeaf(
            lane: voiceLane,
            expectedParent: optimisticMessage,
            expectedAttachment: durablePendingAttachment,
            upload: (allowedPeers) => runUploadMedia(
              uploadMediaFn: voiceLane.uploadMedia,
              bridge: voiceLane.bridge,
              localFilePath: durableAbsolutePath,
              mime: recording.mime,
              recipientPeerId: voiceLane.groupId,
              mediaFileManager: mediaFileManager,
              durationMs: recording.durationMs,
              waveform: waveform,
              allowedPeers: allowedPeers,
              blobId: attachmentId,
            ),
            buildCompleted: (uploaded) => _buildStableVoiceAttachment(
              lane: voiceLane,
              pendingAttachment: durablePendingAttachment,
              uploaded: uploaded,
              absoluteDurablePath: durableAbsolutePath,
              waveform: waveform,
            ),
            replaceExistingAttachments: voiceContinuation != null,
          );
          if (voiceUpload?.completedAttachment != null) {
            _markRelayUploadCompleted(voiceOperation, recording.sizeBytes);
          }
        } finally {
          await _stopRelayUploadTracking(voiceOperation);
        }
        if (!_isCurrentVoiceSendLane(voiceLane, outcome)) return;

        if (voiceUpload == null) {
          if (mounted) {
            _updateComposerState(isUploading: false);
          }
          _restoreActiveQuoteIfNeeded(quotedMessageId);
          return;
        }

        final stableVoiceAttachment = voiceUpload.completedAttachment;
        if (stableVoiceAttachment == null) {
          final projected = voiceUpload.failureProjection;
          if (projected != null) {
            if (mounted) {
              _updateComposerState(isUploading: false);
              _updateLocalMessageStatus(
                messageId,
                projected.isTerminal ? 'failed' : 'queued_offline',
              );
            }
            if (projected.isTerminal) {
              await _trackFailedVoiceContinuation(
                messageId: messageId,
                timestamp: now,
                quotedMessageId: quotedMessageId,
              );
              _restoreActiveQuoteIfNeeded(quotedMessageId);
            }
            return;
          }
          if (mounted) {
            _updateComposerState(isUploading: false);
            _updateLocalMessageStatus(messageId, 'failed');
          }
          await _persistMessageStatus(messageId, 'failed');
          await _trackFailedVoiceContinuation(
            messageId: messageId,
            timestamp: now,
            quotedMessageId: quotedMessageId,
          );
          _restoreActiveQuoteIfNeeded(quotedMessageId);
          return;
        }
        if (mounted) {
          _updateComposerState(isUploading: false);
        }

        final (result, message) = await sendGroupMessage(
          bridge: voiceLane.bridge,
          groupRepo: voiceLane.groupRepository,
          msgRepo: voiceLane.messageRepository,
          groupId: voiceLane.groupId,
          text: '',
          senderPeerId: voiceLane.senderPeerId,
          senderPublicKey: voiceLane.senderPublicKey,
          senderPrivateKey: voiceLane.senderPrivateKey,
          senderUsername: voiceLane.senderUsername,
          messageId: messageId,
          timestamp: now,
          quotedMessageId: quotedMessageId,
          senderDeviceId: voiceLane.senderDeviceId,
          senderTransportPeerId: voiceLane.senderDeviceId,
          mediaAttachments: [stableVoiceAttachment],
          mediaAttachmentRepo: mediaAttachmentRepo,
          inviteDeliveryAttemptRepo: voiceLane.inviteDeliveryAttemptRepository,
        );
        if (!_isCurrentVoiceSendLane(voiceLane, outcome)) return;

        try {
          if ((result == SendGroupMessageResult.success ||
                  result == SendGroupMessageResult.successNoPeers) &&
              message != null) {
            List<MediaAttachment>? displayMedia;
            if (mounted) {
              displayMedia = [];
              for (final a in [stableVoiceAttachment]) {
                if (a.localPath != null) {
                  final absPath = await mediaFileManager.resolveStoredPath(
                    a.localPath!,
                  );
                  displayMedia.add(a.copyWith(localPath: absPath));
                } else {
                  displayMedia.add(a);
                }
              }
            }
            if (mounted) {
              setState(() {
                _upsertMessage(message);
                if (displayMedia != null && displayMedia.isNotEmpty) {
                  _updateMediaForMessage(messageId, displayMedia);
                }
              });
            }
            try {
              await mediaFileManager.deletePendingUploadDir(messageId);
            } catch (_) {}
            _clearRestoredVoiceContinuationTracking(messageId: messageId);
          } else if (result == SendGroupMessageResult.queuedOffline &&
              message != null) {
            // 210b (voice parity): the realistic offline contract — the use
            // case already persisted the durable 'queued_offline' row. Keep the
            // voice bubble on the clock (no failed continuation, no quote
            // restore) and surface the honest snackbar, exactly as the text
            // path does.
            _clearRestoredVoiceContinuationTracking(messageId: messageId);
            await _markOutgoingMessageQueuedOffline(messageId);
            _showOfflineQueuedSnackBar();
            // Staging cleanup mirrors the voice happy branch: the durable
            // stable copy was persisted before the send (review 210b-F6).
            try {
              await mediaFileManager.deletePendingUploadDir(messageId);
            } catch (_) {}
          } else if (result == SendGroupMessageResult.groupNotFound ||
              result == SendGroupMessageResult.groupDissolved ||
              result == SendGroupMessageResult.unauthorized) {
            // 144: keep the voice bubble + recorded audio as a durable,
            // non-retryable send_failed row and latch the composer read-only
            // (the row + attachment were already persisted above). Previously
            // this unconditionally deleted both and flashed a snackbar.
            _clearRestoredVoiceContinuationTracking(messageId: messageId);
            _updateLocalMessageStatus(messageId, GroupMessage.statusSendFailed);
            await _persistMessageStatus(
              messageId,
              GroupMessage.statusSendFailed,
            );
            _restoreActiveQuoteIfNeeded(quotedMessageId);
            if (result == SendGroupMessageResult.groupDissolved) {
              await _refreshVisibleGroup();
            }
            _setTerminalSendReadOnly(_terminalReadOnlyForSendResult(result));
          } else if (!voiceLane.p2pService.currentState.relayReady &&
              message != null) {
            // 210 (voice path parity): offline connectivity failure with a
            // durable row → keep it 'queued_offline' (clock), do NOT restore the
            // quote/composer to a failed state, and show the offline snackbar.
            // Ordered after the terminal checks, as in the text path.
            _clearRestoredVoiceContinuationTracking(messageId: messageId);
            await _markOutgoingMessageQueuedOffline(messageId);
            _showOfflineQueuedSnackBar();
          } else {
            _updateLocalMessageStatus(messageId, 'failed');
            await _persistMessageStatus(messageId, 'failed');
            await _trackFailedVoiceContinuation(
              messageId: messageId,
              timestamp: now,
              quotedMessageId: quotedMessageId,
            );
            _restoreActiveQuoteIfNeeded(quotedMessageId);
          }
        } catch (_) {}
      } finally {
        await _stopRelayUploadTracking(voiceOperation);
        await _endBackgroundTaskGuarded(bgTaskId, bridge: voiceLane.bridge);
      }
    } finally {
      final lease = voiceUploadLease;
      if (lease != null) {
        mediaUploadInFlightTracker.release(lease);
      }
      _endSendFlow();
    }
  }

  Future<void> _cleanupUnsentVoiceArtifacts({
    required String messageId,
    required MediaAttachmentRepository mediaAttachmentRepo,
    required MediaFileManager mediaFileManager,
    required GroupMessageRepository messageRepository,
  }) async {
    if (mounted) {
      _removeLocalMessage(messageId);
    }
    try {
      await mediaAttachmentRepo.deleteAttachmentsForMessage(
        messageId,
        owner: MediaOwnerLane.group,
      );
    } catch (_) {}
    try {
      await mediaFileManager.deletePendingUploadDir(messageId);
    } catch (_) {}
    try {
      await messageRepository.deleteMessage(messageId);
    } catch (_) {}
  }

  Future<MediaAttachment> _buildStableVoiceAttachment({
    required _GroupConversationSendLane lane,
    required MediaAttachment pendingAttachment,
    required MediaAttachment uploaded,
    required String absoluteDurablePath,
    required List<double> waveform,
  }) async {
    final mediaFileManager = lane.mediaFileManager;
    final sourceFile = File(absoluteDurablePath);
    final contentHash =
        uploaded.contentHash ??
        pendingAttachment.contentHash ??
        (await sourceFile.exists()
            ? await GroupMediaIntegrityPolicy.computeFileSha256Hex(
                absoluteDurablePath,
              )
            : null);

    if (mediaFileManager == null) {
      return uploaded.copyWith(
        id: pendingAttachment.id,
        messageId: pendingAttachment.messageId,
        mime: pendingAttachment.mime,
        size: uploaded.size > 0 ? uploaded.size : pendingAttachment.size,
        mediaType: pendingAttachment.mediaType,
        durationMs: uploaded.durationMs ?? pendingAttachment.durationMs,
        localPath: uploaded.localPath ?? absoluteDurablePath,
        waveform: uploaded.waveform ?? waveform,
        downloadStatus: 'done',
        uploadRetryCount: pendingAttachment.uploadRetryCount,
        contentHash: contentHash,
      );
    }

    final absoluteOwnedPath = await mediaFileManager.localPathForAttachment(
      contactPeerId: lane.groupId,
      blobId: pendingAttachment.id,
      mime: pendingAttachment.mime,
    );
    if (await sourceFile.exists() && absoluteOwnedPath != absoluteDurablePath) {
      final targetFile = File(absoluteOwnedPath);
      final parent = targetFile.parent;
      if (!await parent.exists()) {
        await parent.create(recursive: true);
      }
      await sourceFile.copy(absoluteOwnedPath);
    }

    return uploaded.copyWith(
      id: pendingAttachment.id,
      messageId: pendingAttachment.messageId,
      mime: pendingAttachment.mime,
      size: uploaded.size > 0 ? uploaded.size : pendingAttachment.size,
      mediaType: pendingAttachment.mediaType,
      durationMs: uploaded.durationMs ?? pendingAttachment.durationMs,
      localPath: mediaFileManager.relativePathForAttachment(
        contactPeerId: lane.groupId,
        blobId: pendingAttachment.id,
        mime: pendingAttachment.mime,
      ),
      waveform: uploaded.waveform ?? waveform,
      downloadStatus: 'done',
      uploadRetryCount: pendingAttachment.uploadRetryCount,
      contentHash: contentHash,
    );
  }

  void _restoreActiveQuoteIfNeeded(String? quotedMessageId) {
    if (!mounted || quotedMessageId == null || quotedMessageId.isEmpty) return;
    setState(() => _activeQuoteMessageId = quotedMessageId);
  }

  void _onQuoteReply(String messageId) {
    if (!_canWrite) return;
    if (_activeQuoteMessageId != messageId) {
      _clearRestoredMediaContinuationTracking();
      _clearRestoredVoiceContinuationTracking();
    }
    setState(() {
      _activeQuoteMessageId = messageId;
    });
  }

  void _onClearQuote() {
    if (_activeQuoteMessageId == null) return;
    _clearRestoredMediaContinuationTracking();
    _clearRestoredVoiceContinuationTracking();
    setState(() {
      _activeQuoteMessageId = null;
    });
  }

  (String?, bool) _resolveActiveQuotePreview() {
    final activeQuoteMessageId = _activeQuoteMessageId;
    if (activeQuoteMessageId == null || activeQuoteMessageId.isEmpty) {
      return (null, false);
    }

    final quoted = _messages.cast<GroupMessage?>().firstWhere(
      (message) => message?.id == activeQuoteMessageId,
      orElse: () => null,
    );
    if (quoted == null) {
      return (null, true);
    }

    final quotedMedia = _mediaMap[quoted.id] ?? quoted.media;
    return resolveGroupQuotedPreview(
      quoted: quoted,
      quotedMedia: quotedMedia,
      privatePlaceholder: AppLocalizations.of(context)!.media_unavailable,
    );
  }

  Future<void> _onRecordCancel() async {
    if (!_canWrite) return;
    if (!_voiceCaptureController.state.isActive) {
      return;
    }
    await _voiceCaptureController.cancel();
  }

  void _onVoiceCaptureAutoStopOutcome(ConversationVoiceCaptureOutcome outcome) {
    if (!_voiceCaptureController.isCurrentOutcome(outcome) || !mounted) return;
    // The recorder stopped itself at the max recording duration without any
    // user gesture; resync the composer. Auto-send is deliberately out of
    // scope. The group lane neither deletes, reviews, nor sends the controller
    // outcome; recorder mechanics do not decide that lane policy.
    _updateComposerState(
      recordingState: VoiceRecordingState.idle,
      recordingDuration: Duration.zero,
      amplitudeValues: const [],
    );
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_CONV_FL_RECORD_AUTO_STOPPED',
      details: {'tooShort': outcome.recording == null},
    );
  }

  /// Cancels an in-flight recording when the user loses write access or the
  /// visible group changes. The record handlers no-op once [_canWrite] is
  /// false (and the screen nulls them out), so without this an active
  /// recorder would be stranded until auto-stop or dispose.
  void _forceCancelActiveRecording() {
    final voiceState = _voiceCaptureController.state;
    if (!voiceState.isActive && !_voiceCaptureController.hasActiveSession) {
      return;
    }
    final hadActiveSession = _voiceCaptureController.hasActiveSession;
    unawaited(_voiceCaptureController.cancel());
    // Preserve the group lane's existing write-loss projection: a live
    // recording leaves the composer immediately while owner-checked recorder
    // cleanup finishes asynchronously. Arming remains visibly stopping until
    // its in-flight start reaches the controller's abort path.
    if (voiceState.phase != ConversationVoiceCapturePhase.arming) {
      _updateComposerState(
        recordingState: VoiceRecordingState.idle,
        recordingDuration: Duration.zero,
        amplitudeValues: const [],
      );
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_CONV_FL_RECORD_FORCE_CANCELLED',
      details: {'ownedSession': hadActiveSession},
    );
  }

  // -------------------------------------------------------------------------
  // Media tap (full screen viewer)
  // -------------------------------------------------------------------------

  Future<AnnouncementPrivateReplyResolution> _resolveAnnouncementPrivateReply(
    AnnouncementPrivateReplyRequest request,
  ) {
    final resolver = _announcementPrivateReplyResolver;
    if (resolver == null) {
      return Future<AnnouncementPrivateReplyResolution>.value(
        AnnouncementPrivateReplyResolution.unavailable,
      );
    }
    return resolver.resolve(
      request,
      hasCompleteOpener: widget.openAnnouncementSenderConversation != null,
    );
  }

  Future<bool> _isMessageSenderEligible(
    String messageId,
    String senderPeerId,
  ) async {
    final request = AnnouncementPrivateReplyRequest(
      sourceMessageId: messageId,
      senderPeerId: senderPeerId,
    );
    return (await _resolveAnnouncementPrivateReply(request)).isAvailable;
  }

  Future<void> _onMessageSenderTap(
    String messageId,
    String senderPeerId,
  ) async {
    await _dispatchAnnouncementPrivateReply(
      AnnouncementPrivateReplyRequest(
        sourceMessageId: messageId,
        senderPeerId: senderPeerId,
      ),
    );
  }

  String _viewerPrivateReplyKey(MediaViewerItem item) =>
      '${item.messageId}\u0000${item.attachmentId}';

  void _showAnnouncementPrivateReplyFeedback(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<MediaViewerActionResult> _dispatchAnnouncementPrivateReply(
    AnnouncementPrivateReplyRequest selectedRequest, {
    VoidCallback? dismissAfterResolution,
  }) async {
    if (_announcementPrivateReplyDispatchInFlight) {
      return MediaViewerActionResult.cancelled;
    }
    _announcementPrivateReplyDispatchInFlight = true;
    try {
      // Re-read every Session-02 authority using the exact selection-time
      // message/sender anchor. A drifted sender denies; it is never replaced
      // with the newly loaded value.
      final resolution = await _resolveAnnouncementPrivateReply(
        selectedRequest,
      );
      if (!mounted) return MediaViewerActionResult.failure;

      // Viewer callers keep the transient surface alive during the fresh read,
      // then dismiss it before either feedback or navigation. Bubble callers
      // have already dismissed synchronously and pass no callback.
      dismissAfterResolution?.call();
      if (!resolution.isAvailable) {
        _showAnnouncementPrivateReplyFeedback(
          AppLocalizations.of(context)!.announcement_private_reply_unavailable,
        );
        return MediaViewerActionResult.failure;
      }

      final opener = widget.openAnnouncementSenderConversation;
      final contact = resolution.contact;
      if (opener == null || contact == null) {
        _showAnnouncementPrivateReplyFeedback(
          AppLocalizations.of(context)!.announcement_private_reply_unavailable,
        );
        return MediaViewerActionResult.failure;
      }
      try {
        await opener(contact);
        return MediaViewerActionResult.success;
      } catch (_) {
        if (!mounted) return MediaViewerActionResult.failure;
        _showAnnouncementPrivateReplyFeedback(
          AppLocalizations.of(context)!.announcement_private_reply_open_failed,
        );
        return MediaViewerActionResult.failure;
      }
    } finally {
      _announcementPrivateReplyDispatchInFlight = false;
    }
  }

  Future<({GroupMessage parent, MediaAttachment attachment})?>
  _loadCurrentOrdinaryGroupMediaIdentity({
    required String groupId,
    required String messageId,
    required String attachmentId,
    required bool requireIncoming,
  }) async {
    final parent = await widget.msgRepo.getMessage(messageId);
    if (parent == null ||
        parent.groupId != groupId ||
        (requireIncoming && !parent.isIncoming) ||
        parent.privateMediaPolicy.requiresRedaction) {
      return null;
    }
    final tombstoneGroupId = await widget.msgRepo.getLocalDeletionGroupId(
      messageId,
    );
    if (tombstoneGroupId == groupId) return null;

    final mediaRepository = widget.mediaAttachmentRepo;
    if (mediaRepository == null) return null;
    final rows = await mediaRepository.getAttachmentsForMessage(
      messageId,
      owner: MediaOwnerLane.group,
    );
    MediaAttachment? matchedAttachment;
    for (final attachment in rows) {
      if (attachment.id == attachmentId &&
          attachment.messageId == messageId &&
          attachment.ownerLane == MediaOwnerLane.group &&
          (attachment.mediaType == 'image' ||
              attachment.mediaType == 'video')) {
        matchedAttachment = attachment;
        break;
      }
    }
    if (matchedAttachment == null) return null;

    // Tombstone and attachment qualification are await boundaries. Reload the
    // exact parent after both, immediately before any caller can materialize a
    // viewer item, thumbnail, path, or Info metadata.
    final currentParent = await widget.msgRepo.getMessage(messageId);
    if (currentParent == null ||
        currentParent.groupId != groupId ||
        (requireIncoming && !currentParent.isIncoming) ||
        currentParent.privateMediaPolicy.requiresRedaction) {
      return null;
    }
    return (parent: currentParent, attachment: matchedAttachment);
  }

  Future<MediaPictureInPictureAuthorization?>
  _loadGroupPictureInPictureAuthorization(MediaViewerItem displayed) async {
    if (!mounted ||
        displayed.owner != MediaOwnerLane.group ||
        !displayed.isVideo) {
      return null;
    }
    final current = await _loadCurrentOrdinaryGroupMediaIdentity(
      groupId: _group.id,
      messageId: displayed.messageId,
      attachmentId: displayed.attachmentId,
      requireIncoming: true,
    );
    if (!mounted || current == null) return null;
    final attachment = current.attachment;
    if (attachment.mediaType != 'video') return null;
    final storedPath = attachment.localPath;
    final resolvedPath = storedPath == null || storedPath.isEmpty
        ? null
        : MediaFileManager.resolveStoredPathSync(storedPath);
    final hasBytes = resolvedPath != null && File(resolvedPath).existsSync();
    final transferComplete =
        attachment.downloadStatus == kMediaDownloadStatusDone;
    final integrityVerified =
        GroupMediaIntegrityPolicy.hasRequiredVerificationMetadata(attachment);
    final item = MediaViewerItem(
      attachmentId: attachment.id,
      messageId: attachment.messageId,
      kind: MediaViewerKind.video,
      mime: attachment.mime,
      owner: MediaOwnerLane.group,
      localPath: resolvedPath,
      sizeBytes: attachment.size > 0 ? attachment.size : null,
      width: attachment.width,
      height: attachment.height,
      durationMs: attachment.durationMs,
      canEnterPictureInPicture: true,
      protection: MediaViewerProtection(
        isDownloaded: transferComplete && hasBytes,
        isIntegrityVerified: integrityVerified,
      ),
    );
    return MediaPictureInPictureAuthorization(
      item: item,
      generation:
          Object.hash(MediaOwnerLane.group, item.messageId, item.attachmentId) &
          0x7fffffff,
      policyState: MediaPictureInPicturePolicyState.ordinary,
      isIncoming: current.parent.isIncoming,
      isTransferComplete: transferComplete,
      routeActive: mounted,
    );
  }

  GroupPrivateMediaViewerController? get _privateMediaViewerController {
    final existing = _lazyPrivateMediaViewerController;
    if (existing != null) return existing;
    final messages = widget.msgRepo;
    final media = widget.mediaAttachmentRepo;
    final files = widget.mediaFileManager;
    if (!widget.privateMediaAvailability.isEnabled ||
        messages is! GroupPrivateMediaLifecycleRepository ||
        media == null ||
        media is! GroupPrivateMediaCleanupRepository ||
        media is! GroupPrivateMediaCleanupRuntime ||
        files == null) {
      return null;
    }
    final lifecycleMessages = messages as GroupPrivateMediaLifecycleRepository;
    final cleanupMedia = media as GroupPrivateMediaCleanupRepository;
    final cleanupRuntime = media as GroupPrivateMediaCleanupRuntime;
    final engine = GroupPrivateMediaLifecycleEngine(
      messageRepository: lifecycleMessages,
      mediaAttachmentRepository: media,
      cleanupRepository: cleanupMedia,
      mediaFileManager: files,
      lifecycleLock: cleanupRuntime.groupPrivateMediaLifecycleLock,
      nowMs: () => DateTime.now().toUtc().millisecondsSinceEpoch,
    );
    return _lazyPrivateMediaViewerController =
        GroupPrivateMediaViewerController(
          lifecycleEngine: engine,
          protectionCoordinator:
              PrivateMediaProtectionCoordinator.sharedPlatform(),
          disposeProtectionCoordinator: false,
        );
  }

  Future<void> _openGroupPrivateMedia(String messageId) async {
    final controller = _privateMediaViewerController;
    final mediaRepository = widget.mediaAttachmentRepo;
    final fileManager = widget.mediaFileManager;
    if (controller == null || mediaRepository == null || fileManager == null) {
      return;
    }
    var parent = await widget.msgRepo.getMessage(messageId);
    if (parent == null ||
        parent.groupId != _group.id ||
        !parent.isIncoming ||
        !parent.privateMediaPolicy.isPrivate ||
        parent.mediaConsumedAt != null ||
        parent.mediaExpiredAt != null ||
        parent.mediaCleanupPending) {
      return;
    }
    var rows = await mediaRepository.getAttachmentsForMessage(
      messageId,
      owner: MediaOwnerLane.group,
    );
    if (rows.length != 1) return;
    var attachment = rows.single;
    final identity = GroupPrivateMediaViewerIdentity(
      groupId: _group.id,
      messageId: messageId,
      attachmentId: attachment.id,
    );
    if (!_privateMediaOpenInFlight.add(identity)) return;
    try {
      if (attachment.downloadStatus != kMediaDownloadStatusDone ||
          attachment.localPath == null ||
          attachment.localPath!.isEmpty) {
        final downloaded = await downloadMedia(
          bridge: widget.bridge,
          mediaAttachmentRepo: mediaRepository,
          mediaFileManager: fileManager,
          attachment: attachment,
          contactPeerId: _group.id,
          owner: MediaOwnerLane.group,
          groupMessageRepo: widget.msgRepo,
          intent: MediaDownloadIntent.explicitUser,
          enforceGroupMediaPolicy: true,
        );
        if (downloaded == null) return;
        rows = await mediaRepository.getAttachmentsForMessage(
          messageId,
          owner: MediaOwnerLane.group,
        );
        if (rows.length != 1) return;
        attachment = rows.single;
      }
      parent = await widget.msgRepo.getMessage(messageId);
      if (parent == null ||
          parent.groupId != _group.id ||
          parent.mediaConsumedAt != null ||
          parent.mediaExpiredAt != null ||
          parent.mediaCleanupPending) {
        return;
      }
      final grant = await controller.prepare(identity);
      if (grant == null) return;
      if (!mounted) {
        await controller.settle(
          grant,
          GroupPrivateMediaExitReason.routePushFailure,
        );
        return;
      }
      try {
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) =>
                GroupPrivateMediaViewer(grant: grant, controller: controller),
          ),
        );
      } catch (_) {
        await controller.settle(
          grant,
          GroupPrivateMediaExitReason.routePushFailure,
        );
      } finally {
        if (mounted) await _applyMessageUpdate(parent, markAsRead: false);
      }
    } finally {
      _privateMediaOpenInFlight.remove(identity);
    }
  }

  Future<bool> _showCurrentGroupMediaInfo({
    required String messageId,
    required String attachmentId,
  }) async {
    final current = await _loadCurrentOrdinaryGroupMediaIdentity(
      groupId: _group.id,
      messageId: messageId,
      attachmentId: attachmentId,
      requireIncoming: true,
    );
    if (current == null || !mounted) return false;
    await GroupMediaInfoSheet.show(
      context,
      attachment: current.attachment,
      senderDisplayName: _senderLabelFor(current.parent) ?? '',
      sentAt: current.parent.timestamp,
      caption: current.parent.text,
    );
    return true;
  }

  Future<void> _onMediaTap(String messageId, int index) async {
    final message = await widget.msgRepo.getMessage(messageId);
    if (message == null ||
        message.groupId != _group.id ||
        message.privateMediaPolicy.requiresRedaction) {
      return;
    }
    final tombstoneGroupId = await widget.msgRepo.getLocalDeletionGroupId(
      messageId,
    );
    if (tombstoneGroupId == _group.id) return;
    final attachments = _mediaMap[messageId];
    if (attachments == null) return;

    final visual = attachments
        .where((a) => a.mediaType == 'image' || a.mediaType == 'video')
        .toList();
    if (index >= visual.length ||
        !GroupMediaIntegrityPolicy.canDisplayVerifiedGroupMedia(
          visual[index],
        )) {
      return;
    }
    // 235: typed viewer with exact per-attachment identity. The page list is
    // ONLY this parent's displayable attachments — no conversation-wide swipe
    // navigation (library navigation is plan 237).
    final displayable = visual
        .where(GroupMediaIntegrityPolicy.canDisplayVerifiedGroupMedia)
        .toList();
    if (displayable.isEmpty) return;
    final tappedId = visual[index].id;
    var startIndex = displayable.indexWhere((a) => a.id == tappedId);
    if (startIndex < 0) startIndex = 0;
    final selectedRequest = AnnouncementPrivateReplyRequest(
      sourceMessageId: message.id,
      senderPeerId: message.senderPeerId,
    );
    final messageSenderEligible = (await _resolveAnnouncementPrivateReply(
      selectedRequest,
    )).isAvailable;
    if (!mounted) return;
    final items = displayable
        .map(
          (attachment) => _viewerItemFor(
            message,
            attachment,
            allowMessageSender: messageSenderEligible,
          ),
        )
        .toList();

    if (messageSenderEligible) {
      for (final item in items) {
        if (item.capabilities.allows(MediaViewerAction.messageSender)) {
          _viewerPrivateReplyRequests[_viewerPrivateReplyKey(item)] =
              selectedRequest;
        }
      }
    }
    try {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => FullScreenTypedMediaViewer(
            items: items,
            initialIndex: startIndex,
            onAction: _onViewerAction,
            resumeStore: _mediaViewerResumeStore,
            pictureInPictureControllerFactory: _mediaViewerResumeStore == null
                ? null
                : _createMediaPictureInPictureController,
            loadPictureInPictureAuthorization: _mediaViewerResumeStore == null
                ? null
                : _loadGroupPictureInPictureAuthorization,
          ),
        ),
      );
    } finally {
      for (final item in items) {
        _viewerPrivateReplyRequests.remove(_viewerPrivateReplyKey(item));
      }
    }
  }

  String? _senderLabelFor(GroupMessage? message) {
    if (message == null) return null;
    if (!message.isIncoming) {
      return AppLocalizations.of(context)!.feed_you;
    }
    return resolveGroupSenderDisplayName(
      senderPeerId: message.senderPeerId,
      wireSenderUsername: message.senderUsername,
      member: _membersByPeerId[message.senderPeerId],
      preferMemberName: true,
    );
  }

  MediaViewerItem _viewerItemFor(
    GroupMessage? message,
    MediaAttachment attachment, {
    required bool allowMessageSender,
  }) {
    // No trusted parent row -> no capabilities; the item stays view-only.
    final capabilities = message == null
        ? const <GroupReceivedMediaAction>{}
        : GroupReceivedMediaActionPolicy.capabilitiesFor(
            groupType: _group.type,
            isIncoming: message.isIncoming,
            attachment: attachment,
            canWrite: _canWrite,
            mediaPolicy: message.privateMediaPolicy,
          );
    final allowed = <MediaViewerAction>{
      if (_mediaActionsController != null &&
          capabilities.contains(GroupReceivedMediaAction.save))
        MediaViewerAction.save,
      if (_mediaActionsController != null &&
          capabilities.contains(GroupReceivedMediaAction.share))
        MediaViewerAction.share,
      if (capabilities.contains(GroupReceivedMediaAction.info))
        MediaViewerAction.info,
      if (_mediaDeleteForMeCoordinator != null &&
          capabilities.contains(GroupReceivedMediaAction.deleteForMe))
        MediaViewerAction.delete,
      if (capabilities.contains(GroupReceivedMediaAction.reply))
        MediaViewerAction.reply,
      if (allowMessageSender &&
          message != null &&
          !message.privateMediaPolicy.requiresRedaction &&
          attachment.messageId == message.id &&
          attachment.ownerLane == MediaOwnerLane.group &&
          (attachment.mediaType == 'image' || attachment.mediaType == 'video'))
        MediaViewerAction.messageSender,
      // 236: Forward only for eligible incoming verified ordinary media in a
      // discussion group, and only when a forward launch path exists. The
      // request builder and the dispatch gate re-verify everything again.
      if (_canLaunchForward &&
          message != null &&
          GroupMediaForwardPolicy.canOfferForward(
            groupType: _group.type,
            isIncoming: message.isIncoming,
            attachment: attachment,
            mediaPolicy: message.privateMediaPolicy,
          ))
        MediaViewerAction.forward,
    };
    final localPath = attachment.localPath;
    final resolvedPath = localPath == null || localPath.isEmpty
        ? null
        : MediaFileManager.resolveStoredPathSync(localPath);
    final hasBytes = resolvedPath != null && File(resolvedPath).existsSync();
    final integrityVerified =
        GroupMediaIntegrityPolicy.hasRequiredVerificationMetadata(attachment);
    final caption = message?.text.trim();
    return MediaViewerItem(
      attachmentId: attachment.id,
      messageId: attachment.messageId,
      kind: attachment.mediaType == 'video'
          ? MediaViewerKind.video
          : (attachment.isAnimated
                ? MediaViewerKind.gif
                : MediaViewerKind.image),
      mime: attachment.mime,
      owner: MediaOwnerLane.group,
      localPath: resolvedPath,
      sizeBytes: attachment.size > 0 ? attachment.size : null,
      width: attachment.width,
      height: attachment.height,
      durationMs: attachment.durationMs,
      caption: caption == null || caption.isEmpty ? null : caption,
      senderLabel: _senderLabelFor(message),
      timestamp: message?.timestamp,
      canEnterPictureInPicture:
          message?.isIncoming == true &&
          !message!.privateMediaPolicy.requiresRedaction &&
          attachment.mediaType == 'video' &&
          attachment.downloadStatus == kMediaDownloadStatusDone &&
          integrityVerified &&
          hasBytes,
      protection: MediaViewerProtection(
        isDownloaded:
            attachment.downloadStatus == kMediaDownloadStatusDone && hasBytes,
        isIntegrityVerified: integrityVerified,
      ),
      capabilities: MediaViewerActionCapabilities(allowed: allowed),
    );
  }

  Future<MediaViewerActionResult> _onViewerAction(
    MediaViewerItem item,
    MediaViewerAction action,
  ) async {
    switch (action) {
      case MediaViewerAction.save:
        final controller = _mediaActionsController;
        if (controller == null) return MediaViewerActionResult.failure;
        final attempt = await controller.save(
          groupId: _group.id,
          messageId: item.messageId,
          attachmentId: item.attachmentId,
        );
        return _egressAttemptToViewerResult(attempt);
      case MediaViewerAction.share:
        final controller = _mediaActionsController;
        if (controller == null) return MediaViewerActionResult.failure;
        final attempt = await controller.share(
          groupId: _group.id,
          messageId: item.messageId,
          attachmentId: item.attachmentId,
        );
        return _egressAttemptToViewerResult(attempt);
      case MediaViewerAction.delete:
        final deleted = await _confirmAndDeleteForMe(item.messageId);
        if (!deleted) return MediaViewerActionResult.cancelled;
        // The parent (and its media) is gone locally; leave the viewer.
        if (mounted) Navigator.of(context).pop();
        return MediaViewerActionResult.success;
      case MediaViewerAction.info:
        return await _showCurrentGroupMediaInfo(
              messageId: item.messageId,
              attachmentId: item.attachmentId,
            )
            ? MediaViewerActionResult.success
            : MediaViewerActionResult.failure;
      case MediaViewerAction.reply:
        if (!_canWrite) return MediaViewerActionResult.failure;
        if (mounted) Navigator.of(context).pop();
        _onQuoteReply(item.messageId);
        return MediaViewerActionResult.success;
      case MediaViewerAction.messageSender:
        final request =
            _viewerPrivateReplyRequests[_viewerPrivateReplyKey(item)];
        if (request == null) {
          if (mounted && Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
          _showAnnouncementPrivateReplyFeedback(
            AppLocalizations.of(
              context,
            )!.announcement_private_reply_unavailable,
          );
          return MediaViewerActionResult.failure;
        }
        return _dispatchAnnouncementPrivateReply(
          request,
          dismissAfterResolution: () {
            if (mounted && Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          },
        );
      case MediaViewerAction.forward:
        final launched = await _forwardGroupReceivedMedia(
          messageId: item.messageId,
          attachmentId: item.attachmentId,
        );
        return launched
            ? MediaViewerActionResult.success
            : MediaViewerActionResult.failure;
      case MediaViewerAction.bookmark:
        // Not offered here (bookmark is the library surface). Capabilities
        // never include it on this screen.
        return MediaViewerActionResult.failure;
    }
  }

  /// 236: whether ANY forward launch path exists — an injected launcher, or
  /// the full dependency set the fallback share-picker route needs.
  bool get _canLaunchForward {
    if (widget.groupMediaForwardLauncher != null) return true;
    return widget.forwardMessageRepository != null &&
        widget.forwardChatMessageListener != null &&
        widget.mediaAttachmentRepo != null &&
        widget.mediaFileManager != null &&
        widget.imageProcessor != null;
  }

  bool get _canLaunchBatchForward =>
      widget.forwardMessageRepository != null &&
      widget.forwardChatMessageListener != null &&
      widget.mediaAttachmentRepo != null &&
      widget.mediaFileManager != null &&
      widget.imageProcessor != null;

  /// 236: builds one accepted forward request from freshly reloaded rows and
  /// opens the share target picker in forward mode. Only the stable
  /// `(groupId, messageId, attachmentId)` identity and the seed caption cross
  /// this boundary — dispatch re-verifies the source at send time.
  Future<bool> _forwardGroupReceivedMedia({
    required String messageId,
    required String attachmentId,
  }) async {
    final mediaRepo = widget.mediaAttachmentRepo;
    if (mediaRepo == null) return false;
    final request = await GroupMediaForwardRequestBuilder(
      messageRepository: widget.msgRepo,
      mediaAttachmentRepository: mediaRepo,
    ).build(group: _group, messageId: messageId, attachmentId: attachmentId);
    if (request == null || !mounted) return false;

    final injected = widget.groupMediaForwardLauncher;
    if (injected != null) {
      await injected(context, request);
      return true;
    }

    final messageRepository = widget.forwardMessageRepository;
    final chatMessageListener = widget.forwardChatMessageListener;
    final mediaFileManager = widget.mediaFileManager;
    final imageProcessor = widget.imageProcessor;
    if (messageRepository == null ||
        chatMessageListener == null ||
        mediaFileManager == null ||
        imageProcessor == null) {
      return false;
    }

    // Preview and dispatch share the same locked canonical source qualifier.
    // Preview returns no snapshot, while dispatch still captures an immutable
    // copy immediately before delivery.
    final preview = await GroupMediaForwardPreviewGate(
      groupRepository: widget.groupRepo,
      messageRepository: widget.msgRepo,
      mediaAttachmentRepository: mediaRepo,
      mediaFileManager: mediaFileManager,
      isLifecycleRestricted: _mediaActionsController?.isEgressRestricted,
    ).verify(groupType: _group.type, request: request);
    final resolvedPreviewPath = preview.resolvedPath;
    if (resolvedPreviewPath == null || !mounted) return false;

    final initialCaption = switch (request) {
      AnnouncementMediaForwardRequest announcement =>
        announcement.composedCaption,
      _ => request.initialCaption,
    };
    await Navigator.of(context).push(
      buildShareTargetPickerRoute(
        shareIntent: ShareIntent(
          type: initialCaption == null || initialCaption.isEmpty
              ? ShareIntentType.files
              : ShareIntentType.mixed,
          text: initialCaption == null || initialCaption.isEmpty
              ? null
              : initialCaption,
          filePaths: [resolvedPreviewPath],
        ),
        identityRepo: widget.identityRepo,
        contactRepository: widget.contactRepo,
        messageRepository: messageRepository,
        mediaAttachmentRepository: mediaRepo,
        chatMessageListener: chatMessageListener,
        bridge: widget.bridge,
        p2pService: widget.p2pService,
        mediaFileManager: mediaFileManager,
        imageProcessor: imageProcessor,
        groupRepository: widget.groupRepo,
        groupMessageRepository: widget.msgRepo,
        groupInviteDeliveryAttemptRepository: widget.inviteDeliveryAttemptRepo,
        groupMessageListener: widget.groupMessageListener,
        groupConversationTracker: widget.groupConversationTracker,
        groupMediaForwardRequest: request,
      ),
    );
    return true;
  }

  Future<GroupMediaBatchForwardLibraryLaunchResult>
  _forwardGroupSharedMediaBatch({
    required GroupModel sourceGroup,
    required List<GroupSharedMediaIdentity> identities,
  }) async {
    if (!_canLaunchBatchForward ||
        identities.length < kGroupMediaBatchForwardRouteMinItems ||
        identities.length > kGroupMediaBatchForwardMaxItems) {
      return const GroupMediaBatchForwardLibraryLaunchResult.denied(
        GroupMediaBatchForwardDenial.invalidSelection,
      );
    }
    final mediaRepo = widget.mediaAttachmentRepo!;
    final mediaFileManager = widget.mediaFileManager!;
    final requestBuilder = GroupMediaForwardRequestBuilder(
      messageRepository: widget.msgRepo,
      mediaAttachmentRepository: mediaRepo,
      isLifecycleRestricted: _mediaActionsController?.isEgressRestricted,
    );
    final sourceGate = GroupMediaForwardSourceGate(
      groupRepository: widget.groupRepo,
      messageRepository: widget.msgRepo,
      mediaAttachmentRepository: mediaRepo,
      mediaFileManager: mediaFileManager,
      isLifecycleRestricted: _mediaActionsController?.isEgressRestricted,
    );
    final draftBuilder = GroupMediaBatchForwardDraftBuilder.fromPolicies(
      groupRepository: widget.groupRepo,
      messageRepository: widget.msgRepo,
      requestBuilder: requestBuilder,
      sourceGate: sourceGate,
    );
    final built = await draftBuilder.build(
      sourceGroup: sourceGroup,
      identities: identities,
    );
    final draft = built.draft;
    if (!built.isReady || draft == null || !mounted) {
      return GroupMediaBatchForwardLibraryLaunchResult.denied(
        built.denial ?? GroupMediaBatchForwardDenial.sourceUnavailable,
      );
    }

    final ordinary = DefaultShareBatchDeliveryCoordinator(
      identityRepository: widget.identityRepo,
      contactRepository: widget.contactRepo,
      messageRepository: widget.forwardMessageRepository!,
      mediaAttachmentRepository: mediaRepo,
      groupRepository: widget.groupRepo,
      groupMessageRepository: widget.msgRepo,
      groupInviteDeliveryAttemptRepository: widget.inviteDeliveryAttemptRepo,
      bridge: widget.bridge,
      p2pService: widget.p2pService,
      mediaFileManager: mediaFileManager,
      imageProcessor: widget.imageProcessor!,
      shareStoredOfflinePromise: AppLocalizations.of(
        context,
      )!.share_stored_offline_promise,
    );
    final delivery = GroupMediaBatchForwardDeliveryCoordinator(
      revalidateForDispatch: draftBuilder.revalidateForDispatch,
      deliverSingle: ordinary.deliverGroupMediaForward,
    );
    final completion = await Navigator.of(context).push(
      buildGroupMediaBatchForwardPickerRoute(
        draft: draft,
        identityRepository: widget.identityRepo,
        contactRepository: widget.contactRepo,
        groupRepository: widget.groupRepo,
        deliveryCoordinator: delivery,
      ),
    );
    if (completion == null) {
      return const GroupMediaBatchForwardLibraryLaunchResult.cancelled();
    }
    return GroupMediaBatchForwardLibraryLaunchResult.completed(completion);
  }

  MediaViewerActionResult _egressAttemptToViewerResult(
    GroupReceivedMediaEgressAttempt attempt,
  ) {
    final result = attempt.result;
    if (result == null) return MediaViewerActionResult.failure;
    switch (result.outcome) {
      case MediaEgressOutcome.saved:
      case MediaEgressOutcome.presented:
        return MediaViewerActionResult.success;
      case MediaEgressOutcome.cancelled:
        return MediaViewerActionResult.cancelled;
      case MediaEgressOutcome.partial:
      case MediaEgressOutcome.busy:
      case MediaEgressOutcome.permissionDenied:
      case MediaEgressOutcome.rejected:
      case MediaEgressOutcome.platformFailure:
        return MediaViewerActionResult.failure;
    }
  }

  // ---------------------------------------------------------------------
  // 235: bubble-initiated received-media actions
  // ---------------------------------------------------------------------

  Future<void> _onMediaSave(String messageId, String attachmentId) async {
    final controller = _mediaActionsController;
    if (controller == null) return;
    final attempt = await controller.save(
      groupId: _group.id,
      messageId: messageId,
      attachmentId: attachmentId,
    );
    if (!mounted) return;
    if (attempt.result?.outcome == MediaEgressOutcome.saved) {
      showQuietConfirm(
        context,
        AppLocalizations.of(context)!.group_media_saved_confirm,
      );
    }
  }

  Future<void> _onMediaShare(String messageId, String attachmentId) async {
    final controller = _mediaActionsController;
    if (controller == null) return;
    // The OS share sheet is its own visible outcome; no extra confirm cue.
    await controller.share(
      groupId: _group.id,
      messageId: messageId,
      attachmentId: attachmentId,
    );
  }

  Future<void> _onMediaDeleteForMe(String messageId) async {
    await _confirmAndDeleteForMe(messageId);
  }

  /// Returns true only when the user confirmed AND the coordinator ran.
  /// Cancel is a zero-op; a second confirm while one is in flight for the
  /// same parent coalesces to a no-op.
  Future<bool> _confirmAndDeleteForMe(String messageId) async {
    final coordinator = _mediaDeleteForMeCoordinator;
    if (coordinator == null || !mounted) return false;
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.group_media_delete_for_me_title),
        content: Text(l10n.group_media_delete_for_me_body),
        actions: [
          TextButton(
            key: const ValueKey('group-media-delete-cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.group_media_delete_for_me_cancel),
          ),
          TextButton(
            key: const ValueKey('group-media-delete-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.group_media_delete_for_me_confirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return false;
    final flightKey = '${_group.id}:$messageId';
    if (!_deleteForMeInFlight.add(flightKey)) return false;
    try {
      await coordinator.deleteForMe(groupId: _group.id, messageId: messageId);
      return true;
    } finally {
      _deleteForMeInFlight.remove(flightKey);
    }
  }

  // -------------------------------------------------------------------------
  // Navigation
  // -------------------------------------------------------------------------

  Future<void> _onBack() async {
    final shouldPop = await _confirmLeaveWhileUploadActive();
    if (!shouldPop || !mounted) return;
    setState(() => _allowPopDuringActiveUpload = true);
    Navigator.of(context).pop();
  }

  Future<void> _onInfo() async {
    final mediaRepo = widget.mediaAttachmentRepo;
    final libraryAvailable =
        (_group.type == GroupType.chat ||
            _group.type == GroupType.announcement) &&
        !_group.isDissolved &&
        mediaRepo is MediaLibraryRepository &&
        mediaRepo is MediaLibraryStateRepository;
    final result = await Navigator.of(context).push<Object?>(
      MaterialPageRoute(
        builder: (_) => GroupInfoWired(
          group: _group,
          groupRepo: widget.groupRepo,
          msgRepo: widget.msgRepo,
          inviteDeliveryAttemptRepo: widget.inviteDeliveryAttemptRepo,
          contactRepo: widget.contactRepo,
          bridge: widget.bridge,
          identityRepo: widget.identityRepo,
          p2pService: widget.p2pService,
          imageProcessor: widget.imageProcessor,
          mediaPicker: widget.mediaPicker,
          backgroundPreference: widget.backgroundPreference,
          sharedMediaRouteBuilder: libraryAvailable
              ? (_, liveGroup) => _buildSharedMediaLibrary(
                  liveGroup,
                  mediaRepo as MediaAttachmentRepository,
                )
              : null,
        ),
      ),
    );
    if (!mounted) return;
    await _refreshAfterInfoRoute();
    if (!mounted) return;
    if (result is GroupSharedMediaGoToMessage) {
      await _goToSharedMediaMessage(result);
    }
  }

  Widget _buildSharedMediaLibrary(
    GroupModel liveGroup,
    MediaAttachmentRepository mediaRepo,
  ) {
    final libraryRepo = mediaRepo as MediaLibraryRepository;
    final stateRepo = mediaRepo as MediaLibraryStateRepository;
    final deleteCoordinator = _mediaDeleteForMeCoordinator;
    final canEvict =
        mediaRepo is MediaAttachmentByIdLookup &&
        mediaRepo is MediaDownloadStateRepository;
    final storage = canEvict
        ? MediaStorageManager(
            repository: mediaRepo,
            documentsDirectoryProvider: () async =>
                (await getApplicationDocumentsDirectory()).path,
          )
        : null;
    final mediaActionsController = _mediaActionsController;
    final batchActions = GroupSharedMediaBatchActionsCoordinator(
      messageRepository: widget.msgRepo,
      mediaAttachmentRepository: mediaRepo,
      egressService:
          mediaActionsController?.egressService ?? ReceivedMediaEgressService(),
      mediaFileManager:
          widget.mediaFileManager ?? mediaActionsController?.mediaFileManager,
      isEgressRestricted: mediaActionsController?.isEgressRestricted,
      requestIdFactory: mediaActionsController?.requestIdFactory,
      stateRepository: stateRepo,
      clearLocalCopy: storage == null
          ? null
          : ({required scope, required attachmentId, required mime}) =>
                storage.clearLocalCopy(
                  scope: scope,
                  attachmentId: attachmentId,
                  mime: mime,
                ),
    );
    final batchDelete = deleteCoordinator == null
        ? null
        : GroupSharedMediaBatchDeleteCoordinator(
            messageRepository: widget.msgRepo,
            coordinator: deleteCoordinator,
          );
    return GroupSharedMediaLibraryScreen(
      groupId: liveGroup.id,
      incomingOnly: liveGroup.type == GroupType.announcement,
      libraryRepository: libraryRepo,
      stateRepository: stateRepo,
      capabilitiesForEntry: (entry) {
        final attachment = entry.attachment;
        final ownPeerId = _ownPeerId;
        final senderPeerId = entry.parentSenderPeerId;
        final incoming =
            ownPeerId != null &&
            senderPeerId != null &&
            senderPeerId != ownPeerId;
        final lifecycleRestricted =
            _mediaActionsController?.isEgressRestricted(attachment) ?? false;
        final egressEligible =
            incoming &&
            !lifecycleRestricted &&
            GroupMediaIntegrityPolicy.canDisplayVerifiedGroupMedia(attachment);
        final forwardEligible =
            _canLaunchForward &&
            GroupMediaForwardPolicy.canOfferForward(
              groupType: liveGroup.type,
              isIncoming: incoming,
              attachment: attachment,
              isLifecycleRestricted:
                  _mediaActionsController?.isEgressRestricted,
            );
        return {
          GroupSharedMediaAction.bookmark,
          GroupSharedMediaAction.goToMessage,
          if (deleteCoordinator != null) GroupSharedMediaAction.delete,
          if (storage != null &&
              attachment.downloadStatus == kMediaDownloadStatusDone &&
              attachment.localPath != null)
            GroupSharedMediaAction.evict,
          if (egressEligible) ...{
            GroupSharedMediaAction.save,
            GroupSharedMediaAction.share,
            if (attachment.mediaType == 'video')
              GroupSharedMediaAction.pictureInPicture,
            if (forwardEligible) GroupSharedMediaAction.forward,
          },
        };
      },
      pictureInPictureControllerFactory: _createMediaPictureInPictureController,
      loadPictureInPictureAuthorization:
          _loadGroupPictureInPictureAuthorization,
      mediaViewerResumeStore: _mediaViewerResumeStore,
      dispatchEgress: (identities, destination) => batchActions
          .performBatchEgress(identities: identities, destination: destination),
      dispatchDelete: deleteCoordinator == null
          ? null
          : (identities) =>
                batchDelete!.perform(identities: identities, confirmed: true),
      dispatchBookmark: (identities) => batchActions.performBatchBookmark(
        identities: identities,
        bookmarked: true,
      ),
      dispatchEviction: storage == null
          ? null
          : (entries) async {
              final result = await batchActions.performBatchClear(
                identities: [
                  for (final entry in entries)
                    GroupSharedMediaIdentity(
                      groupId: liveGroup.id,
                      messageId: entry.attachment.messageId,
                      attachmentId: entry.attachment.id,
                    ),
                ],
              );
              return result.succeededIds;
            },
      dispatchForward: _canLaunchForward
          ? (identity) => _forwardGroupReceivedMedia(
              messageId: identity.messageId,
              attachmentId: identity.attachmentId,
            )
          : null,
      launchBatchForward: _canLaunchBatchForward
          ? (identities) => _forwardGroupSharedMediaBatch(
              sourceGroup: liveGroup,
              identities: identities,
            )
          : null,
      qualifyViewerEntry: (identity) async =>
          await _loadCurrentOrdinaryGroupMediaIdentity(
            groupId: identity.groupId,
            messageId: identity.messageId,
            attachmentId: identity.attachmentId,
            requireIncoming: false,
          ) !=
          null,
      onMessagesDeleted: (messageIds) {
        for (final messageId in messageIds) {
          _removeLocalMessage(messageId);
        }
      },
    );
  }

  void _invalidateSharedMediaAnchorReplay() {
    _sharedMediaAnchorReplayGroupId = null;
    _sharedMediaAnchorReplayTargetId = null;
    _sharedMediaAnchorReplayWindow = const <GroupMessage>[];
    _sharedMediaAnchorReplayMedia = const <String, List<MediaAttachment>>{};
    _sharedMediaAnchorReplayLoadGenerations = const <int>{};
  }

  void _consumeSharedMediaAnchorReplay(int loadGeneration) {
    if (!_sharedMediaAnchorReplayLoadGenerations.contains(loadGeneration)) {
      return;
    }
    final remaining = <int>{..._sharedMediaAnchorReplayLoadGenerations}
      ..remove(loadGeneration);
    if (remaining.isEmpty) {
      _invalidateSharedMediaAnchorReplay();
      return;
    }
    _sharedMediaAnchorReplayLoadGenerations = remaining;
  }

  void _clearActiveSharedMediaAnchor({required bool clearHighlight}) {
    final priorTargetId = _activeSharedMediaAnchorTargetId;
    final injectedIds = _activeSharedMediaAnchorInjectedIds;
    if (injectedIds.isNotEmpty) {
      _messages = _messages
          .where((message) => !injectedIds.contains(message.id))
          .toList(growable: false);
      final nextMedia = Map<String, List<MediaAttachment>>.from(_mediaMap);
      for (final messageId in injectedIds) {
        nextMedia.remove(messageId);
      }
      _mediaMap = nextMedia;
    }
    if (clearHighlight && _highlightedMessageId == priorTargetId) {
      _highlightedMessageId = null;
      _highlightScrollResolved = false;
    }
    _activeSharedMediaAnchorGroupId = null;
    _activeSharedMediaAnchorTargetId = null;
    _activeSharedMediaAnchorInjectedIds = const <String>{};
    _invalidateSharedMediaAnchorReplay();
  }

  Future<void> _goToSharedMediaMessage(
    GroupSharedMediaGoToMessage result,
  ) async {
    final requestGroupId = _group.id;
    final mutationGenerationAtStart = _messageMutationGeneration;
    final window = await _sharedMediaAnchorRequests.load(
      repository: widget.msgRepo,
      currentGroupId: requestGroupId,
      requestedGroupId: result.groupId,
      messageId: result.messageId,
    );
    if (window == null ||
        !mounted ||
        widget.group.id != requestGroupId ||
        _group.id != requestGroupId) {
      return;
    }
    final loadsInFlightWhenAnchorResolved = <int>{
      ..._activeMessageLoadGenerations,
    };
    var currentWindow = window
        .where(
          (message) =>
              message.groupId == requestGroupId &&
              !_locallyRemovedMessageIds.contains(message.id),
        )
        .toList(growable: false);
    if (!currentWindow.any((message) => message.id == result.messageId)) {
      setState(() => _clearActiveSharedMediaAnchor(clearHighlight: true));
      return;
    }
    final hydrated = await _loadResolvedMediaMap(currentWindow);
    if (!mounted ||
        widget.group.id != requestGroupId ||
        _group.id != requestGroupId) {
      return;
    }
    currentWindow = currentWindow
        .where((message) => !_locallyRemovedMessageIds.contains(message.id))
        .toList(growable: false);
    if (!currentWindow.any((message) => message.id == result.messageId)) {
      setState(() => _clearActiveSharedMediaAnchor(clearHighlight: true));
      return;
    }

    final stillInFlightReplayGenerations = loadsInFlightWhenAnchorResolved
        .where(_activeMessageLoadGenerations.contains)
        .toSet();
    final priorInjectedIds = _activeSharedMediaAnchorGroupId == requestGroupId
        ? _activeSharedMediaAnchorInjectedIds
        : const <String>{};
    final byId = <String, GroupMessage>{
      for (final message in _messages)
        if (message.groupId == requestGroupId &&
            !priorInjectedIds.contains(message.id) &&
            !_locallyRemovedMessageIds.contains(message.id))
          message.id: message,
    };
    final baseIds = byId.keys.toSet();
    for (final message in currentWindow) {
      byId[message.id] = message;
    }
    final currentMutatedRows = <String, GroupMessage>{
      for (final message in _messages)
        if (message.groupId == requestGroupId &&
            !_locallyRemovedMessageIds.contains(message.id) &&
            _messageMutatedAfter(message.id, mutationGenerationAtStart))
          message.id: message,
    };
    byId.addAll(currentMutatedRows);
    for (final messageId in _locallyRemovedMessageIds) {
      byId.remove(messageId);
    }
    final nextMedia = Map<String, List<MediaAttachment>>.from(_mediaMap);
    for (final messageId in priorInjectedIds) {
      nextMedia.remove(messageId);
    }
    final windowIds = currentWindow.map((message) => message.id).toSet();
    for (final entry in hydrated.entries) {
      if (windowIds.contains(entry.key) &&
          !_locallyRemovedMessageIds.contains(entry.key)) {
        nextMedia[entry.key] = entry.value;
      }
    }
    for (final messageId in currentMutatedRows.keys) {
      final currentMedia = _mediaMap[messageId];
      if (currentMedia == null) {
        nextMedia.remove(messageId);
      } else {
        nextMedia[messageId] = currentMedia;
      }
    }
    for (final messageId in _locallyRemovedMessageIds) {
      nextMedia.remove(messageId);
    }
    final replayWindow = windowIds
        .map((messageId) => byId[messageId])
        .whereType<GroupMessage>()
        .toList(growable: false);
    setState(() {
      _messages = orderGroupMessagesForTimeline(byId.values);
      _mediaMap = nextMedia;
      _activeSharedMediaAnchorGroupId = requestGroupId;
      _activeSharedMediaAnchorTargetId = result.messageId;
      _activeSharedMediaAnchorInjectedIds = windowIds
          .where((messageId) => !baseIds.contains(messageId))
          .toSet();
      _highlightedMessageId = result.messageId;
      _highlightScrollResolved = false;
      if (stillInFlightReplayGenerations.isEmpty) {
        _invalidateSharedMediaAnchorReplay();
      } else {
        _sharedMediaAnchorReplayGroupId = requestGroupId;
        _sharedMediaAnchorReplayTargetId = result.messageId;
        _sharedMediaAnchorReplayWindow = List<GroupMessage>.unmodifiable(
          replayWindow,
        );
        _sharedMediaAnchorReplayMedia = {
          for (final entry in nextMedia.entries)
            if (windowIds.contains(entry.key)) entry.key: entry.value,
        };
        _sharedMediaAnchorReplayLoadGenerations =
            stillInFlightReplayGenerations;
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollToHighlightedMessage();
    });
  }

  bool _canWriteForGroup(GroupModel group) {
    if (group.isDissolved) {
      return false;
    }
    if (!_isCurrentUserActiveMember) {
      return false;
    }
    if (!_hasCurrentSendKey) {
      return false;
    }
    if (!_hasCompleteSenderIdentity) {
      return false;
    }
    if (group.type == GroupType.announcement &&
        group.myRole != GroupRole.admin) {
      return false;
    }
    return true;
  }

  String get _readOnlyBannerText {
    final l10n = AppLocalizations.of(context)!;
    if (_groupExitIntent != null) {
      return l10n.group_exit_leaving_read_only;
    }
    if (_exitIntentLookupStatus != GroupExitIntentLookupStatus.available) {
      return l10n.group_read_only_unavailable;
    }
    switch (_terminalSendReadOnly) {
      case _TerminalReadOnly.dissolved:
        return l10n.group_read_only_dissolved;
      case _TerminalReadOnly.removed:
        return l10n.group_read_only_not_active;
      case _TerminalReadOnly.unavailable:
        return l10n.group_read_only_unavailable;
      case _TerminalReadOnly.none:
        break;
    }
    if (_group.isDissolved) {
      return l10n.group_read_only_dissolved;
    }
    if (!_isCurrentUserActiveMember) {
      return l10n.group_read_only_not_active;
    }
    if (!_hasCurrentSendKey) {
      return l10n.group_read_only_waiting_key;
    }
    if (!_hasCompleteSenderIdentity) {
      return l10n.group_read_only_waiting_identity;
    }
    return l10n.group_read_only_admin_only;
  }

  /// The per-message "Couldn't send — …" reason for a terminal `send_failed`
  /// bubble. Null while no terminal send/reaction failure is latched, so a
  /// retry-exhausted `send_failed` row in a still-writable group never shows a
  /// terminal reason (144 INV-4).
  String? get _terminalSendFailedReasonText {
    final l10n = AppLocalizations.of(context)!;
    switch (_terminalSendReadOnly) {
      case _TerminalReadOnly.none:
        return null;
      case _TerminalReadOnly.dissolved:
        return l10n.group_send_failed_dissolved;
      case _TerminalReadOnly.removed:
        return l10n.group_send_failed_removed;
      case _TerminalReadOnly.unavailable:
        return l10n.group_send_failed_unavailable;
    }
  }

  _TerminalReadOnly _terminalReadOnlyForSendResult(
    SendGroupMessageResult result,
  ) {
    switch (result) {
      case SendGroupMessageResult.groupDissolved:
        return _TerminalReadOnly.dissolved;
      case SendGroupMessageResult.unauthorized:
        return _TerminalReadOnly.removed;
      case SendGroupMessageResult.groupNotFound:
        return _TerminalReadOnly.unavailable;
      default:
        return _TerminalReadOnly.none;
    }
  }

  void _setTerminalSendReadOnly(_TerminalReadOnly value) {
    if (_terminalSendReadOnly == value) return;
    final hadWriteAccess = _canWrite;
    if (mounted) {
      setState(() => _terminalSendReadOnly = value);
    } else {
      _terminalSendReadOnly = value;
    }
    if (hadWriteAccess && !_canWrite) {
      _forceCancelActiveRecording();
    }
  }

  /// 144: self-heal a `removed`/`unavailable` terminal read-only latch when the
  /// divergence that caused it has demonstrably resolved IN PLACE — so the
  /// composer reappears without leaving the conversation (parity with the live
  /// membership self-heal).
  ///
  /// `removed` clears only on a POSITIVE re-add (members non-empty AND includes
  /// self) and only when the group is otherwise writable — never the fails-open
  /// empty-members read that produced the divergence, which would defeat the
  /// latch. `unavailable` clears when a fresh group read returns the row again.
  /// `dissolved` never self-heals (a dissolved group does not un-dissolve;
  /// `_canWriteForGroup`'s isDissolved check keeps it read-only regardless).
  void _maybeReleaseRecoveredTerminalReadOnly({
    List<GroupMember>? members,
    bool groupReappeared = false,
  }) {
    switch (_terminalSendReadOnly) {
      case _TerminalReadOnly.removed:
        final ownPeerId = _ownPeerId;
        final positivelyAMember =
            members != null &&
            ownPeerId != null &&
            members.isNotEmpty &&
            members.any((member) => member.peerId == ownPeerId);
        if (positivelyAMember && _canWriteForGroup(_group)) {
          _setTerminalSendReadOnly(_TerminalReadOnly.none);
        }
      case _TerminalReadOnly.unavailable:
        if (groupReappeared) {
          _setTerminalSendReadOnly(_TerminalReadOnly.none);
        }
      case _TerminalReadOnly.dissolved:
      case _TerminalReadOnly.none:
        break;
    }
  }

  bool _hasOwnTerminalSendFailedRow() {
    final ownPeerId = _ownPeerId;
    if (ownPeerId == null) return false;
    return _messages.any(
      (message) =>
          !message.isIncoming &&
          message.senderPeerId == ownPeerId &&
          message.status == GroupMessage.statusSendFailed,
    );
  }

  /// 144 finding: reconstruct the terminal read-only latch on a fresh mount /
  /// reopen so a persisted `send_failed` bubble keeps its "Couldn't send — …"
  /// reason + Delete and the composer stays read-only — the in-memory latch set
  /// during the original send does not survive a rebuild.
  ///
  /// Only acts when the latch is unset (never overrides a live send/reaction
  /// latch nor a just-released self-heal) AND there is an own persisted terminal
  /// row to explain (so a healthy group, a brand-new group, or the startup
  /// window is untouched — this keeps INV-4: a retry-exhausted `send_failed` row
  /// in a still-writable group reconstructs NOTHING because self is present).
  ///
  /// `removed` (not `dissolved`) is used for the membership-empty/excludes-self
  /// case because it self-heals on a later positive re-add via
  /// [_maybeReleaseRecoveredTerminalReadOnly]; a transiently-empty read can
  /// never strand the composer permanently. `dissolved` is reserved for a row
  /// the group itself marks dissolved (which cannot un-dissolve).
  void _hydrateTerminalReadOnlyFromState() {
    if (_terminalSendReadOnly != _TerminalReadOnly.none) return;
    if (_ownPeerId == null) return;
    if (!_hasOwnTerminalSendFailedRow()) return;
    if (_group.isDissolved) {
      _setTerminalSendReadOnly(_TerminalReadOnly.dissolved);
      return;
    }
    // Membership-based reconstruction needs a completed security load — before
    // that _membersByPeerId is empty for the startup window, not a removal.
    if (!_securityStatusLoaded) return;
    final selfPresent = _membersByPeerId.containsKey(_ownPeerId);
    if (!selfPresent) {
      _setTerminalSendReadOnly(_TerminalReadOnly.removed);
    }
  }

  /// Clears a terminal `send_failed` bubble (and any durable artifacts) when the
  /// user taps Delete. Stays reachable even while the composer is read-only so a
  /// stuck bubble in a dead group can always be removed (144).
  Future<void> _onDeleteFailedTerminalMessage(String messageId) async {
    _clearRestoredVoiceContinuationTracking(messageId: messageId);
    // 144 finding: a terminal media/voice send keeps a `done` attachment that
    // was already relocated to the durable owned location (media/<groupId>/...),
    // which deletePendingUploadDir below does NOT cover. Unlink those files
    // BEFORE the attachment rows are dropped (the file paths live on the rows),
    // or the durable media orphans on disk.
    late final List<MediaAttachment> attachments;
    try {
      attachments =
          await widget.mediaAttachmentRepo?.getAttachmentsForMessage(
            messageId,
            owner: MediaOwnerLane.group,
          ) ??
          const <MediaAttachment>[];
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_CONV_FL_TERMINAL_MEDIA_DELETE_ERROR',
        details: {'stage': 'load_attachments', 'error': error.toString()},
      );
      return;
    }
    final mediaFileManager = widget.mediaFileManager;
    if (attachments.isNotEmpty && mediaFileManager == null) return;
    try {
      for (final attachment in attachments) {
        await _deleteCanonicalOwnedGroupMediaFile(attachment);
      }
      await mediaFileManager?.deletePendingUploadDir(messageId);
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_CONV_FL_TERMINAL_MEDIA_DELETE_ERROR',
        details: {'stage': 'delete_files', 'error': error.toString()},
      );
      return;
    }
    try {
      await widget.mediaAttachmentRepo?.deleteAttachmentsForMessage(
        messageId,
        owner: MediaOwnerLane.group,
      );
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_CONV_FL_TERMINAL_MEDIA_DELETE_ERROR',
        details: {'stage': 'delete_attachment_rows', 'error': error.toString()},
      );
      return;
    }
    try {
      await widget.msgRepo.deleteMessage(messageId);
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_CONV_FL_TERMINAL_MEDIA_DELETE_ERROR',
        details: {'stage': 'delete_message_row', 'error': error.toString()},
      );
      return;
    }
    _removeLocalMessage(messageId);
  }

  bool _canWriteForSnapshot({
    required GroupModel group,
    required bool isCurrentUserActiveMember,
    required bool hasCurrentSendKey,
    required bool hasCompleteSenderIdentity,
  }) {
    if (group.isDissolved) {
      return false;
    }
    if (!isCurrentUserActiveMember || !hasCurrentSendKey) {
      return false;
    }
    if (!hasCompleteSenderIdentity) {
      return false;
    }
    if (group.type == GroupType.announcement &&
        group.myRole != GroupRole.admin) {
      return false;
    }
    return true;
  }

  Future<bool> _refreshSendCapabilityAndCanWrite() async {
    final identity = !_hasCompleteSenderIdentity
        ? await widget.identityRepo.loadIdentity()
        : null;
    final ownPeerId = _ownPeerId ?? identity?.peerId;
    final senderUsername = identity?.username ?? _senderUsername;
    final senderPublicKey = identity?.publicKey ?? _senderPublicKey;
    final senderPrivateKey = identity?.privateKey ?? _senderPrivateKey;
    final hasCompleteSenderIdentity = _hasCompleteSenderIdentityFields(
      peerId: ownPeerId,
      username: senderUsername,
      publicKey: senderPublicKey,
      privateKey: senderPrivateKey,
    );
    final latestKey = await widget.groupRepo.getLatestKey(widget.group.id);
    final members = await widget.groupRepo.getMembers(widget.group.id);
    final isCurrentUserActiveMember =
        ownPeerId == null ||
        members.isEmpty ||
        members.any((member) => member.peerId == ownPeerId);
    final hasCurrentSendKey = latestKey != null;

    if (!mounted) {
      return false;
    }
    final hadWriteAccess = _canWrite;
    if (identity != null ||
        _isCurrentUserActiveMember != isCurrentUserActiveMember ||
        _hasCurrentSendKey != hasCurrentSendKey) {
      setState(() {
        if (identity != null) {
          _ownPeerId = identity.peerId;
          _senderUsername = identity.username;
          _senderPublicKey = identity.publicKey;
          _senderPrivateKey = identity.privateKey;
        }
        _isCurrentUserActiveMember = isCurrentUserActiveMember;
        _hasCurrentSendKey = hasCurrentSendKey;
      });
    }
    if (hadWriteAccess && !_canWrite) {
      _forceCancelActiveRecording();
    }
    _maybeReleaseRecoveredTerminalReadOnly(members: members);
    return _exitIntentLookupStatus == GroupExitIntentLookupStatus.available &&
        _groupExitIntent == null &&
        _terminalSendReadOnly == _TerminalReadOnly.none &&
        _canWriteForSnapshot(
          group: _group,
          isCurrentUserActiveMember: isCurrentUserActiveMember,
          hasCurrentSendKey: hasCurrentSendKey,
          hasCompleteSenderIdentity: hasCompleteSenderIdentity,
        );
  }

  bool _matchesGroupSnapshot(GroupModel a, GroupModel b) {
    return a.id == b.id &&
        a.name == b.name &&
        a.type == b.type &&
        a.topicName == b.topicName &&
        a.description == b.description &&
        a.avatarBlobId == b.avatarBlobId &&
        a.avatarMime == b.avatarMime &&
        a.avatarPath == b.avatarPath &&
        a.createdAt == b.createdAt &&
        a.createdBy == b.createdBy &&
        a.myRole == b.myRole &&
        a.isMuted == b.isMuted &&
        a.isDissolved == b.isDissolved &&
        a.dissolvedAt == b.dissolvedAt &&
        a.dissolvedBy == b.dissolvedBy &&
        a.isArchived == b.isArchived &&
        a.archivedAt == b.archivedAt &&
        a.lastMembershipEventAt == b.lastMembershipEventAt &&
        a.lastMetadataEventAt == b.lastMetadataEventAt &&
        a.lastBacklogExpiredAt == b.lastBacklogExpiredAt &&
        a.lastBacklogRetainedAt == b.lastBacklogRetainedAt;
  }

  bool _isIncomingGroupNewer(GroupModel incoming, GroupModel current) {
    final incomingMembershipAt = incoming.lastMembershipEventAt;
    final currentMembershipAt = current.lastMembershipEventAt;
    if (incomingMembershipAt != null &&
        (currentMembershipAt == null ||
            incomingMembershipAt.isAfter(currentMembershipAt))) {
      return true;
    }

    final incomingMetadataAt = incoming.lastMetadataEventAt;
    final currentMetadataAt = current.lastMetadataEventAt;
    if (incomingMetadataAt != null &&
        (currentMetadataAt == null ||
            incomingMetadataAt.isAfter(currentMetadataAt))) {
      return true;
    }

    return false;
  }

  bool get _canWrite =>
      _exitIntentLookupStatus == GroupExitIntentLookupStatus.available &&
      _groupExitIntent == null &&
      _terminalSendReadOnly == _TerminalReadOnly.none &&
      _canWriteForGroup(_group);

  bool get _canMutateReactions =>
      // 144 finding: a terminal send/reaction read-only latch must also disable
      // the long-press reaction picker (mirrors _canWrite). Otherwise the banner
      // reads read-only while reactions stay tappable, and each tap re-hits the
      // terminal result and silently reverts. Rides the F1 self-heal release.
      _exitIntentLookupStatus == GroupExitIntentLookupStatus.available &&
      _groupExitIntent == null &&
      _terminalSendReadOnly == _TerminalReadOnly.none &&
      _isCurrentUserActiveMember &&
      !_group.isDissolved &&
      widget.reactionRepo != null &&
      widget.groupReactionReplayOutboxRepository != null;

  Future<void> _refreshVisibleGroup() async {
    final refreshedGroup = await widget.groupRepo.getGroup(widget.group.id);
    final historyGapRepair = await widget.historyGapRepairRepo
        ?.getLatestRepairForGroup(widget.group.id);
    if (refreshedGroup == null || !mounted) {
      return;
    }

    final hadWriteAccess = _canWrite;
    setState(() {
      _group = refreshedGroup;
      _historyGapRepair = historyGapRepair;
    });
    if (hadWriteAccess && !_canWrite) {
      _forceCancelActiveRecording();
    }
    // The group row exists again (the early-return above guards null), so a
    // latched `unavailable` terminal read-only can self-heal in place (144).
    _maybeReleaseRecoveredTerminalReadOnly(groupReappeared: true);
  }

  Future<void> _refreshExitIntent() async {
    final groupId = widget.group.id;
    final result = await loadGroupExitIntent(groupId);
    if (!mounted || widget.group.id != groupId) return;

    final hadWriteAccess = _canWrite;
    setState(() {
      _exitIntentLookupStatus = result.status;
      if (result.isAvailable) {
        _groupExitIntent = result.intent;
      }
    });
    if (_groupExitIntent != null) {
      _forceCancelActiveRecording();
      if (_activeQuoteMessageId != null) {
        setState(() => _activeQuoteMessageId = null);
      }
    } else if (hadWriteAccess && !_canWrite) {
      _forceCancelActiveRecording();
    }
  }

  Future<void> _refreshAfterInfoRoute() async {
    await _refreshVisibleGroup();
    await _refreshExitIntent();
    await _loadMessages();
    await _loadSecurityStatus();
  }

  static String _mimeFromPath(String path) {
    final ext = path.split('.').last.toLowerCase();
    const map = {
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'gif': 'image/gif',
      'webp': 'image/webp',
      'heic': 'image/heic',
      'heif': 'image/heic',
      'mp4': 'video/mp4',
      'mov': 'video/quicktime',
      'avi': 'video/x-msvideo',
      'mkv': 'video/x-matroska',
      'm4v': 'video/x-m4v',
      'm4a': 'audio/mp4',
      'aac': 'audio/aac',
    };
    return map[ext] ?? 'application/octet-stream';
  }

  bool _validatePendingGroupMediaDescriptors(List<PendingComposerMedia> media) {
    // Unsupported-MIME is a hard reject of a never-displayable file → it stays a
    // snackbar (out of the per-chip size/GIF scope, 149).
    for (final pending in media) {
      final mime = _mimeFromPath(pending.file.path);
      final validation = GroupMediaMimePolicy.validateDescriptor(
        mime: mime,
        mediaType: GroupMediaMimePolicy.mediaTypeForMime(mime),
      );
      if (validation.isValid) continue;

      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_CONV_FL_MEDIA_REJECTED_INVALID_MIME',
        details: {'mime': mime, 'reason': validation.reason},
      );
      _showFloatingSnackBar(
        AppLocalizations.of(context)!.group_media_unsupported,
      );
      return false;
    }
    // Per-type SEND size gate: iterate `media` ourselves (capturing each index)
    // instead of delegating to GroupMediaSizePolicy.validateAttachments, which
    // discards the index. The inline composer reject-chip already carries the
    // reason (149), so this path is snackbar-free.
    final sizeRejections = collectPendingMediaSizeRejections(
      media,
      _mimeFromPath,
    );
    if (sizeRejections.isNotEmpty) {
      for (final rejection in sizeRejections) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_CONV_FL_MEDIA_REJECTED_INVALID_SIZE',
          details: {'index': rejection.index, 'reason': rejection.reason},
        );
      }
      return false;
    }
    // Whole-message budget (owns no single index) — preserve the prior
    // total-size hard block.
    final totalBytes = media.fold<int>(
      0,
      (sum, pending) => sum + pending.budgetBytes,
    );
    if (totalBytes > kGroupMediaTotalMessageLimitBytes) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_CONV_FL_MEDIA_REJECTED_INVALID_SIZE',
        details: {'reason': 'total_media_size_exceeded'},
      );
      return false;
    }
    return true;
  }

  Future<void> _loadReactions(List<GroupMessage> messages) async {
    if (widget.reactionRepo == null) return;
    final bindingGeneration = _reactionBindingGeneration;
    final groupId = widget.group.id;
    final eligibleMessageIds = messages
        .where((message) => message.privateMediaPolicy.isOrdinary)
        .map((message) => message.id)
        .toList(growable: false);
    final ineligibleMessageIds = messages
        .where((message) => !message.privateMediaPolicy.isOrdinary)
        .map((message) => message.id)
        .toSet();

    final reactionsByMessage = eligibleMessageIds.isEmpty
        ? const <String, List<MessageReaction>>{}
        : await loadReactionsForConversation(
            reactionRepo: widget.reactionRepo!,
            messageIds: eligibleMessageIds,
          );
    if (!mounted ||
        bindingGeneration != _reactionBindingGeneration ||
        widget.group.id != groupId) {
      return;
    }
    _retiredReactionMessageIds.removeAll(messages.map((message) => message.id));

    final nextReactions = Map<String, List<MessageReaction>>.from(
      _reactionProjectionController.reactions,
    );
    for (final messageId in ineligibleMessageIds) {
      nextReactions.remove(messageId);
    }
    nextReactions.addAll(reactionsByMessage);
    _reactionProjectionController.replaceAll(nextReactions);
  }

  void _startListeningForReactions() {
    final bindingGeneration = ++_reactionBindingGeneration;
    final groupId = widget.group.id;
    _reactionSubscription = widget
        .groupMessageListener
        .groupReactionChangeStream
        .listen((change) {
          if (_isCurrentReactionBinding(bindingGeneration, groupId)) {
            _onIncomingReactionChange(change);
          }
        });
  }

  void _onIncomingReactionChange(ReactionChange change) {
    if (!mounted || _retiredReactionMessageIds.contains(change.messageId)) {
      return;
    }
    _reactionProjectionController.applyChange(
      change,
      upsertPlacement: ConversationReactionUpsertPlacement.append,
    );
  }

  Future<void> _onReactionSelected(String messageId, String emoji) async {
    if (!_canMutateReactions) return;
    if (_ownPeerId == null) return;
    final bindingGeneration = _reactionBindingGeneration;
    final groupId = widget.group.id;

    final previousReactions = List<MessageReaction>.from(
      _reactionProjectionController.reactionsFor(messageId),
    );

    // Check if we already have a reaction with this emoji — toggle off
    final existing = previousReactions.where(
      (r) => r.senderPeerId == _ownPeerId && r.emoji == emoji,
    );

    if (existing.isNotEmpty) {
      // Optimistic remove
      _reactionProjectionController.applyChange(
        ReactionChange.removed(messageId: messageId, senderPeerId: _ownPeerId!),
      );

      late final RemoveGroupReactionResult result;
      try {
        result = await removeGroupReaction(
          bridge: widget.bridge,
          groupRepo: widget.groupRepo,
          reactionRepo: widget.reactionRepo!,
          reactionReplayOutboxRepo: widget.groupReactionReplayOutboxRepository!,
          groupId: widget.group.id,
          messageId: messageId,
          emoji: emoji,
          senderPeerId: _ownPeerId!,
          senderPublicKey: _senderPublicKey,
          senderPrivateKey: _senderPrivateKey,
        );
      } catch (_) {
        if (_isCurrentReactionBinding(bindingGeneration, groupId)) {
          _restoreReactionState(messageId, previousReactions);
        }
        return;
      }
      if (!_isCurrentReactionBinding(bindingGeneration, groupId)) return;
      // queuedForRetry keeps the optimistic delete: the remove is durably
      // staged and will be re-driven by the retry driver (INV-R1).
      if (result == RemoveGroupReactionResult.success ||
          result == RemoveGroupReactionResult.queuedForRetry) {
        return;
      }
      if (result == RemoveGroupReactionResult.groupDissolved) {
        await _restoreReactionStateAfterDissolve(messageId, previousReactions);
      } else if (result == RemoveGroupReactionResult.notMember) {
        // 144: keep the remove direction's terminal feedback symmetric with the
        // add direction — silent revert + durable read-only banner.
        _restoreReactionState(messageId, previousReactions);
        _setTerminalSendReadOnly(_TerminalReadOnly.removed);
      } else if (result == RemoveGroupReactionResult.groupNotFound) {
        _restoreReactionState(messageId, previousReactions);
        _setTerminalSendReadOnly(_TerminalReadOnly.unavailable);
      } else {
        _restoreReactionState(messageId, previousReactions);
      }
      return;
    }

    // Optimistic add
    final tempReaction = MessageReaction(
      id: '',
      messageId: messageId,
      emoji: emoji,
      senderPeerId: _ownPeerId!,
      timestamp: DateTime.now().toUtc().toIso8601String(),
      createdAt: DateTime.now().toUtc().toIso8601String(),
    );
    _reactionProjectionController.applyChange(
      ReactionChange.upsert(tempReaction),
      upsertPlacement: ConversationReactionUpsertPlacement.append,
    );

    late final SendGroupReactionResult result;
    late final MessageReaction? reaction;
    try {
      final sendResult = await sendGroupReaction(
        bridge: widget.bridge,
        groupRepo: widget.groupRepo,
        msgRepo: widget.msgRepo,
        reactionRepo: widget.reactionRepo!,
        reactionReplayOutboxRepo: widget.groupReactionReplayOutboxRepository!,
        groupId: widget.group.id,
        messageId: messageId,
        emoji: emoji,
        senderPeerId: _ownPeerId!,
        senderPublicKey: _senderPublicKey,
        senderPrivateKey: _senderPrivateKey,
      );
      result = sendResult.$1;
      reaction = sendResult.$2;
    } catch (_) {
      if (_isCurrentReactionBinding(bindingGeneration, groupId)) {
        _restoreReactionState(messageId, previousReactions);
      }
      return;
    }
    if (!_isCurrentReactionBinding(bindingGeneration, groupId)) return;

    final confirmedReaction = reaction;
    // queuedForRetry keeps the emoji: swap the temp for the persisted reaction
    // just like success. The reaction is durably staged and will be re-driven
    // by the retry driver (INV-R1) instead of silently reverted.
    if ((result == SendGroupReactionResult.success ||
            result == SendGroupReactionResult.queuedForRetry) &&
        confirmedReaction != null) {
      _reactionProjectionController.applyChange(
        ReactionChange.upsert(confirmedReaction),
        upsertPlacement: ConversationReactionUpsertPlacement.append,
      );
    } else if (result == SendGroupReactionResult.groupDissolved) {
      await _restoreReactionStateAfterDissolve(messageId, previousReactions);
    } else if (result == SendGroupReactionResult.notMember) {
      // 144: a reaction into a group we are no longer a member of is terminal.
      // Keep the silent revert (a failed-reaction bubble would need a schema
      // change — out of scope) but flip the composer read-only so the user gets
      // durable feedback instead of a silent no-op.
      _restoreReactionState(messageId, previousReactions);
      _setTerminalSendReadOnly(_TerminalReadOnly.removed);
    } else if (result == SendGroupReactionResult.groupNotFound) {
      _restoreReactionState(messageId, previousReactions);
      _setTerminalSendReadOnly(_TerminalReadOnly.unavailable);
    } else {
      _restoreReactionState(messageId, previousReactions);
    }
  }

  void _restoreReactionState(
    String messageId,
    List<MessageReaction> previousReactions,
  ) {
    if (!mounted) return;
    _reactionProjectionController.replaceForMessage(
      messageId,
      previousReactions,
    );
  }

  Future<void> _restoreReactionStateAfterDissolve(
    String messageId,
    List<MessageReaction> previousReactions,
  ) async {
    if (mounted) {
      _reactionProjectionController.replaceForMessage(
        messageId,
        previousReactions,
      );
    }
    await _refreshVisibleGroup();
    // 144 INV-5: the durable read-only banner is the terminal feedback now, not
    // a transient snackbar. The override flips the banner even when the group
    // row has not been marked dissolved locally yet.
    _setTerminalSendReadOnly(_TerminalReadOnly.dissolved);
  }

  Future<void> _onReactionTap(String messageId, String emoji) async {
    final bindingGeneration = _reactionBindingGeneration;
    final groupId = widget.group.id;
    final allReactions = _reactionProjectionController.reactionsFor(messageId);
    if (allReactions.isEmpty) return;

    final members = await widget.groupRepo.getMembers(widget.group.id);
    final usernameHintsByPeerId = await loadGroupReactionUsernameHints(
      peerIds: allReactions.map((reaction) => reaction.senderPeerId),
      contactRepo: widget.contactRepo,
      groupId: widget.group.id,
      msgRepo: widget.msgRepo,
    );
    if (!mounted ||
        bindingGeneration != _reactionBindingGeneration ||
        widget.group.id != groupId) {
      return;
    }

    final participants = buildGroupReactionParticipantEntries(
      reactions: allReactions,
      emoji: emoji,
      members: members,
      usernameHintsByPeerId: usernameHintsByPeerId,
      ownPeerId: _ownPeerId,
      selfLabel: AppLocalizations.of(context)!.feed_you,
    );
    if (participants.isEmpty) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.backgroundReadableColors.surfaceBase,
      showDragHandle: false,
      builder: (_) =>
          GroupReactionDetailsSheet(emoji: emoji, participants: participants),
    );
  }

  bool _isCurrentReactionBinding(int generation, String groupId) =>
      mounted &&
      generation == _reactionBindingGeneration &&
      widget.group.id == groupId;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.groupConversationTracker?.clearIfActive(_activeGroupConversationKey);
    _messageSubscription?.cancel();
    _outgoingLocalMessageChangeSubscription?.cancel();
    _removedSubscription?.cancel();
    _reactionSubscription?.cancel();
    final privateController = _lazyPrivateMediaViewerController;
    _lazyPrivateMediaViewerController = null;
    if (privateController != null) unawaited(privateController.dispose());
    _scrollController.dispose();
    _uploadActivityController.removeListener(_onControllerInvalidated);
    _reactionProjectionController.removeListener(_onControllerInvalidated);
    _voiceCaptureController.removeListener(_onVoiceCaptureStateChanged);
    _uploadActivityController.dispose();
    _reactionProjectionController.dispose();
    _voiceCaptureController.dispose();
    _composerController.dispose();
    super.dispose();
  }

  String get _activeGroupConversationKey => 'group:${widget.group.id}';

  /// 159: the memoized group run-grouped display list. Recomputes only when
  /// `_messages` (reference identity), the locale, or the day token changes;
  /// otherwise returns the cached list. Passed to [GroupConversationScreen] as
  /// `precomputedDisplayItems` (the Stateless screen cannot cache).
  List<GroupDisplayItem> _memoizedGroupDisplayItems(BuildContext context) {
    final locale = Localizations.localeOf(context).toString();
    final now = DateTime.now();
    final todayToken = '${now.year}-${now.month}-${now.day}';
    final cached = _cachedGroupDisplayItems;
    if (cached != null &&
        identical(_messages, _cachedGroupMessagesRef) &&
        _cachedGroupLocale == locale &&
        _cachedGroupTodayToken == todayToken) {
      return cached;
    }
    GroupConversationWired.debugGroupDisplayItemsBuildCount++;
    final result = buildGroupDisplayItems(
      messages: _messages,
      l10n: AppLocalizations.of(context)!,
      locale: locale,
      now: now,
    );
    _cachedGroupDisplayItems = result;
    _cachedGroupMessagesRef = _messages;
    _cachedGroupLocale = locale;
    _cachedGroupTodayToken = todayToken;
    return result;
  }

  @override
  Widget build(BuildContext context) {
    _uploadActivityController.refreshOwnerProjection(publish: false);
    if (!_canWrite && _activeQuoteMessageId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _canWrite || _activeQuoteMessageId == null) return;
        setState(() {
          _activeQuoteMessageId = null;
        });
      });
    }

    final (activeQuoteText, isActiveQuoteUnavailable) = _canWrite
        ? _resolveActiveQuotePreview()
        : (null, false);

    return ValueListenableBuilder<int>(
      valueListenable: groupRecoveryGate.activeDepthListenable,
      builder: (context, recoveryDepth, child) {
        return PopScope(
          canPop: !_isTrackingRelayUpload || _allowPopDuringActiveUpload,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop || !_isTrackingRelayUpload) return;
            unawaited(_onBack());
          },
          child: GroupConversationScreen(
            group: _group,
            messages: _messages,
            precomputedDisplayItems: _memoizedGroupDisplayItems(context),
            membersByPeerId: _membersByPeerId,
            ownPeerId: _ownPeerId,
            onSend: _onSend,
            onBack: _onBack,
            onInfo: _onInfo,
            canWrite: _canWrite,
            readOnlyBannerText: _canWrite ? null : _readOnlyBannerText,
            isSending: _isSending,
            uploadProgress: _uploadActivityController.aggregateProgress,
            messageUploadProgress: _uploadActivityController.messageProgress,
            p2pService: widget.p2pService,
            securityStatus: _securityStatus,
            onCancelUpload:
                _uploadActivityController.activeOperation == null ||
                    _uploadActivityController.cancelRequested
                ? null
                : _requestCancelActiveAttachmentUpload,
            initialLoadDone: _initialLoadDone,
            isRecovering: recoveryDepth > 0,
            messageLoadErrorText: _messageLoadErrorText,
            onRetryMessageLoad: _retryMessageLoad,
            scrollController: _scrollController,
            highlightedMessageId: _highlightedMessageId,
            highlightAnchorKey: _highlightAnchorKey,
            mediaMap: _mediaMap,
            mediaRenderedSemanticsLabels: widget.mediaRenderedSemanticsLabels,
            composerStateListenable: _composerController,
            onRemoveAttachment: _canWrite ? _removeAttachment : null,
            onAttach: _canWrite ? _onAttach : null,
            onRecordStart: _canWrite && _supportsDurableGroupMediaUploads
                ? _onRecordStart
                : null,
            onRecordStop: _canWrite && _supportsDurableGroupMediaUploads
                ? _onRecordStop
                : null,
            onRecordCancel: _canWrite && _supportsDurableGroupMediaUploads
                ? _onRecordCancel
                : null,
            recordingState: _composerController.value.recordingState,
            onMediaTap: _onMediaTap,
            onOpenPrivateMedia: _privateMediaViewerController == null
                ? null
                : (messageId) => unawaited(_openGroupPrivateMedia(messageId)),
            privateMediaEnabled: widget.privateMediaAvailability.isEnabled,
            onMediaSave: _mediaActionsController != null ? _onMediaSave : null,
            onMediaShare: _mediaActionsController != null
                ? _onMediaShare
                : null,
            onMediaInfo: widget.mediaAttachmentRepo != null
                ? (messageId, attachmentId) async {
                    await _showCurrentGroupMediaInfo(
                      messageId: messageId,
                      attachmentId: attachmentId,
                    );
                  }
                : null,
            onMediaDeleteForMe: _mediaDeleteForMeCoordinator != null
                ? _onMediaDeleteForMe
                : null,
            isMessageSenderEligible:
                _announcementPrivateReplyResolver != null &&
                    widget.openAnnouncementSenderConversation != null
                ? _isMessageSenderEligible
                : null,
            onMessageSenderTap:
                _announcementPrivateReplyResolver != null &&
                    widget.openAnnouncementSenderConversation != null
                ? _onMessageSenderTap
                : null,
            reactions: _reactionProjectionController.reactions,
            onReactionTap: _onReactionTap,
            onReactionSelected: _canMutateReactions
                ? _onReactionSelected
                : null,
            initialText: _draftText,
            onDraftChanged: _onDraftChanged,
            onQuoteReply: _canWrite ? _onQuoteReply : null,
            onRetryFailedMessage:
                _canWrite && widget.mediaAttachmentRepo != null
                ? _onRetryFailedMessage
                : null,
            retryingFailedMessageIds: _retryingFailedMessageIds,
            onRetryFailedMedia:
                _canWrite &&
                    widget.mediaAttachmentRepo != null &&
                    widget.mediaFileManager != null
                ? _onRetryFailedMedia
                : null,
            onRetryUnavailableMedia:
                _exitIntentLookupStatus ==
                        GroupExitIntentLookupStatus.available &&
                    _groupExitIntent == null &&
                    widget.mediaAttachmentRepo != null &&
                    widget.mediaFileManager != null
                ? _onRetryUnavailableMedia
                : null,
            onDeleteFailedMedia:
                _canWrite &&
                    widget.mediaAttachmentRepo != null &&
                    widget.mediaFileManager != null
                ? _onDeleteFailedMedia
                : null,
            // 144: terminal send_failed bubbles. The reason text is null unless
            // a terminal failure is latched, and Delete is intentionally NOT
            // gated by _canWrite so a stuck bubble stays clearable in a dead
            // group.
            failedTerminalReasonText: _terminalSendFailedReasonText,
            onDeleteFailedTerminalMessage: _onDeleteFailedTerminalMessage,
            activeQuoteText: activeQuoteText,
            isActiveQuoteUnavailable: isActiveQuoteUnavailable,
            onClearQuote: _canWrite ? _onClearQuote : null,
            backlogRetentionNotice: groupBacklogRetentionNoticeFor(
              _group,
              AppLocalizations.of(context)!,
            ),
            historyGapRepairNotice: groupHistoryGapRepairNoticeFor(
              _historyGapRepair,
              AppLocalizations.of(context)!,
            ),
            backgroundPreference: widget.backgroundPreference,
          ),
        );
      },
    );
  }
}
