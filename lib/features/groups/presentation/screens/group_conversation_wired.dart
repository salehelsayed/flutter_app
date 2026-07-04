import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/core/device/upload_wake_lock.dart';
import 'package:flutter_app/core/media/amplitude_buffer.dart';
import 'package:flutter_app/core/media/audio_recorder_service.dart';
import 'package:flutter_app/features/conversation/domain/models/audio_recording.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/media/downsample_waveform.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/group_media_mime_policy.dart';
import 'package:flutter_app/core/media/group_media_size_policy.dart';
import 'package:flutter_app/core/permissions/mic_permission_gateway.dart';
import 'package:flutter_app/core/permissions/mic_permission_prompt.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_picker.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/pending_composer_media.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/utils/notification_tap_timing.dart';
import 'package:flutter_app/core/constants/retry_constants.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/download_media_use_case.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/media_rejection.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/compose_area.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/upload_progress_banner.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/group_media_allowed_peers.dart';
import 'package:flutter_app/features/groups/application/group_recovery_gate.dart';
import 'package:flutter_app/features/conversation/application/load_reactions_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_change.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/groups/application/remove_group_reaction_use_case.dart';
import 'package:flutter_app/features/groups/application/retry_failed_group_messages_use_case.dart';
import 'package:flutter_app/features/groups/application/retry_incomplete_group_uploads_use_case.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/application/send_group_reaction_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/application/group_member_device_safety.dart';
import 'package:flutter_app/features/groups/domain/models/group_member_identity_safety.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
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
import 'package:flutter_app/features/groups/presentation/widgets/group_reaction_details_sheet.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_app/features/settings/domain/models/image_quality_preference.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/full_screen_image_viewer.dart';
import 'package:flutter_app/shared/widgets/media/media_preview_text.dart';

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
  final int maxAttachmentBudgetBytes;
  final DateTime? notificationTappedAt;
  final BackgroundPreference backgroundPreference;

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
    this.maxAttachmentBudgetBytes = kGeneralMediaAttachmentBudgetBytes,
    this.notificationTappedAt,
    this.backgroundPreference = BackgroundPreference.defaultBackground,
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
  // 144 finding: distinguishes "membership never loaded yet" (startup window —
  // do NOT infer removal) from "loaded and genuinely empty/excluding self".
  // Gates the reopen reconstruction of the terminal read-only latch.
  bool _securityStatusLoaded = false;

  // Media state
  List<PendingComposerMedia> _pendingAttachments = [];
  final _composerState = ValueNotifier(const ConversationComposerViewState());
  Map<String, List<MediaAttachment>> _mediaMap = {};

  // Reaction state
  Map<String, List<MessageReaction>> _reactions = {};
  StreamSubscription<ReactionChange>? _reactionSubscription;
  StreamSubscription<Map<String, dynamic>>? _mediaUploadProgressSubscription;

  // Voice recording state
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<double>? _amplitudeSub;
  final _amplitudeBuffer = AmplitudeBuffer(size: 25);
  List<double> _waveformSamples = [];
  bool _pendingRecorderAbort = false;
  bool _isTrackingRelayUpload = false;
  int _trackedUploadTotalBytes = 0;
  int _trackedUploadCompletedBytes = 0;
  int _trackedCurrentUploadBytes = 0;
  String? _trackedCurrentUploadId;
  bool _allowPopDuringActiveUpload = false;
  _GroupActiveAttachmentUpload? _activeAttachmentUpload;
  _RestoredGroupMediaContinuation? _restoredMediaContinuation;
  _RestoredGroupVoiceContinuation? _restoredVoiceContinuation;

  ConversationComposerViewState get _composerViewState => _composerState.value;

  MediaPicker get _mediaPicker => widget.mediaPicker ?? _defaultMediaPicker;

  String? get _currentSenderDeviceId {
    final peerId = widget.p2pService.currentState.peerId?.trim();
    return peerId == null || peerId.isEmpty ? null : peerId;
  }

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

  Future<String> _beginBackgroundTaskGuarded() async {
    try {
      return await callBgBegin(widget.bridge) ?? '';
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_CONV_FL_BG_BEGIN_ERROR',
        details: {'error': e.toString()},
      );
      return '';
    }
  }

  Future<void> _endBackgroundTaskGuarded(String bgTaskId) async {
    if (bgTaskId.isEmpty) return;
    try {
      await callBgEnd(widget.bridge, bgTaskId);
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_CONV_FL_BG_END_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  bool get _isRecording => _composerViewState.recordingState.isActive;

  UploadProgressViewState? get _uploadProgressViewState {
    if (!_isTrackingRelayUpload || _trackedUploadTotalBytes <= 0) return null;
    return UploadProgressViewState(
      sentBytes: (_trackedUploadCompletedBytes + _trackedCurrentUploadBytes)
          .clamp(0, _trackedUploadTotalBytes)
          .toInt(),
      totalBytes: _trackedUploadTotalBytes,
    );
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
    WidgetsBinding.instance.addObserver(this);
    _group = widget.group;
    _isLifecycleResumed = _currentLifecycleAllowsVisibleRead();
    _draftText = widget.initialText ?? '';
    widget.groupConversationTracker?.setActive(_activeGroupConversationKey);
    _updateComposerState(pendingAttachments: _pendingAttachmentFiles());
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
    _mediaUploadProgressSubscription = mediaUploadProgressStream.listen(
      _handleMediaUploadProgress,
    );
    _loadIdentity();
    _loadMessages();
    unawaited(_loadSecurityStatus());
    _startListening();
    _startListeningForOutgoingLocalMessageChanges();
    _startListeningForReactions();
  }

  bool _notificationTimingEmitted = false;

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

  void _handleMediaUploadProgress(Map<String, dynamic> event) {
    if (!_isTrackingRelayUpload) return;
    final id = event['id'] as String?;
    final sentBytes = event['sentBytes'];
    if (id == null || sentBytes is! num) return;
    if (_trackedCurrentUploadId != null && _trackedCurrentUploadId != id) {
      return;
    }
    final nextBytes = sentBytes
        .toInt()
        .clamp(0, _trackedUploadTotalBytes)
        .toInt();
    if (mounted) {
      setState(() {
        _trackedCurrentUploadId = id;
        _trackedCurrentUploadBytes = nextBytes;
      });
    } else {
      _trackedCurrentUploadId = id;
      _trackedCurrentUploadBytes = nextBytes;
    }
  }

  Future<void> _startRelayUploadTracking(int totalBytes) async {
    if (_isTrackingRelayUpload || totalBytes <= 0) return;
    if (mounted) {
      setState(() {
        _isTrackingRelayUpload = true;
        _trackedUploadTotalBytes = totalBytes;
        _trackedUploadCompletedBytes = 0;
        _trackedCurrentUploadBytes = 0;
        _trackedCurrentUploadId = null;
      });
    } else {
      _isTrackingRelayUpload = true;
      _trackedUploadTotalBytes = totalBytes;
      _trackedUploadCompletedBytes = 0;
      _trackedCurrentUploadBytes = 0;
      _trackedCurrentUploadId = null;
    }
    await UploadWakeLockController.acquire();
  }

  void _markRelayUploadStarted(String uploadId) {
    if (!_isTrackingRelayUpload) return;
    if (mounted) {
      setState(() {
        _trackedCurrentUploadId = uploadId;
        _trackedCurrentUploadBytes = 0;
      });
    } else {
      _trackedCurrentUploadId = uploadId;
      _trackedCurrentUploadBytes = 0;
    }
  }

  void _markRelayUploadCompleted(int sizeBytes) {
    if (!_isTrackingRelayUpload) return;
    final nextCompleted = (_trackedUploadCompletedBytes + sizeBytes)
        .clamp(0, _trackedUploadTotalBytes)
        .toInt();
    if (mounted) {
      setState(() {
        _trackedUploadCompletedBytes = nextCompleted;
        _trackedCurrentUploadBytes = 0;
        _trackedCurrentUploadId = null;
      });
    } else {
      _trackedUploadCompletedBytes = nextCompleted;
      _trackedCurrentUploadBytes = 0;
      _trackedCurrentUploadId = null;
    }
  }

  Future<void> _stopRelayUploadTracking() async {
    if (!_isTrackingRelayUpload) return;
    if (mounted) {
      setState(() {
        _isTrackingRelayUpload = false;
        _trackedUploadTotalBytes = 0;
        _trackedUploadCompletedBytes = 0;
        _trackedCurrentUploadBytes = 0;
        _trackedCurrentUploadId = null;
      });
    } else {
      _isTrackingRelayUpload = false;
      _trackedUploadTotalBytes = 0;
      _trackedUploadCompletedBytes = 0;
      _trackedCurrentUploadBytes = 0;
      _trackedCurrentUploadId = null;
    }
    await UploadWakeLockController.release();
  }

  void _beginActiveAttachmentUpload({
    required String messageId,
    required _GroupComposerSnapshot composerSnapshot,
  }) {
    final next = _GroupActiveAttachmentUpload(
      messageId: messageId,
      composerSnapshot: composerSnapshot,
    );
    if (mounted) {
      setState(() => _activeAttachmentUpload = next);
    } else {
      _activeAttachmentUpload = next;
    }
  }

  void _clearActiveAttachmentUpload() {
    if (_activeAttachmentUpload == null) return;
    if (mounted) {
      setState(() => _activeAttachmentUpload = null);
    } else {
      _activeAttachmentUpload = null;
    }
  }

  void _requestCancelActiveAttachmentUpload() {
    final activeUpload = _activeAttachmentUpload;
    if (activeUpload == null || activeUpload.cancelRequested) {
      return;
    }
    final next = activeUpload.copyWith(cancelRequested: true);
    if (mounted) {
      setState(() => _activeAttachmentUpload = next);
    } else {
      _activeAttachmentUpload = next;
    }
  }

  Future<bool> _cancelActiveAttachmentUploadIfRequested() async {
    final activeUpload = _activeAttachmentUpload;
    if (activeUpload == null || !activeUpload.cancelRequested) {
      return false;
    }
    await widget.mediaAttachmentRepo
        ?.markUploadPendingAttachmentsFailedForMessage(activeUpload.messageId);
    await _stopRelayUploadTracking();
    _clearActiveAttachmentUpload();
    await _restoreComposerSnapshot(
      activeUpload.composerSnapshot,
      activeUpload.messageId,
      snackText: AppLocalizations.of(context)!.upload_cancelled,
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
    _forceCancelActiveRecording();
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

    _group = widget.group;
    _messages = [];
    _mediaMap = {};
    _reactions = {};
    _membersByPeerId = const {};
    _historyGapRepair = null;
    _securityStatus = null;
    _messageLoadErrorText = null;
    // 144: a terminal send-failure latch is per-group; scrub it so a different
    // group does not inherit a stale read-only composer/banner/reason. Also
    // re-enter the startup window (clear _securityStatusLoaded) so the reopen
    // hydration short-circuits until the NEW group's membership has loaded —
    // otherwise a _loadMessages/_loadSecurityStatus race on a same-State
    // group-id change could transiently latch a false `removed`.
    _terminalSendReadOnly = _TerminalReadOnly.none;
    _securityStatusLoaded = false;
    _initialLoadDone = false;
    _activeQuoteMessageId = null;
    _draftText = widget.initialText ?? '';
    _pendingAttachments = [];
    _clearRestoredMediaContinuationTracking();
    _clearRestoredVoiceContinuationTracking();
    _updateComposerState(pendingAttachments: const [], isUploading: false);
    if (mounted) {
      setState(() {});
    }

    _loadMessages();
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
    _pendingAttachments = List<PendingComposerMedia>.from(accepted);
    _updateComposerState(pendingAttachments: _pendingAttachmentFiles());
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
    _pendingAttachments = List<PendingComposerMedia>.from(initialPendingMedia);
    _updateComposerState(pendingAttachments: _pendingAttachmentFiles());
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
    _pendingAttachments = [..._pendingAttachments, ...accepted];
    _updateComposerState(pendingAttachments: _pendingAttachmentFiles());
  }

  Future<List<PendingComposerMedia>?> _resolvePendingMediaCandidates({
    required List<PendingComposerMedia> candidateAttachments,
  }) async {
    if (candidateAttachments.isEmpty) return const [];

    final combinedBudgetBytes = totalPendingComposerBudgetBytes([
      ..._pendingAttachments,
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
      ..._pendingAttachments,
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
    required String draftText,
    required String? quotedMessageId,
    required List<PendingComposerMedia> pendingAttachments,
  }) {
    return continuation.groupId == widget.group.id &&
        continuation.draftText == draftText &&
        _sameOptionalMessageId(continuation.quotedMessageId, quotedMessageId) &&
        continuation.attachmentFingerprint ==
            _pendingAttachmentFingerprint(pendingAttachments);
  }

  Future<({bool handled, _RestoredGroupMediaContinuation? continuation})>
  _resolveRestoredMediaContinuationForSend({
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
      draftText: draftText,
      quotedMessageId: quotedMessageId,
      pendingAttachments: pendingAttachments,
    )) {
      _clearRestoredMediaContinuationTracking();
      return (handled: false, continuation: null);
    }

    final message = await widget.msgRepo.getMessage(continuation.messageId);
    if (!mounted) return (handled: true, continuation: null);
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
      _pendingAttachments = [];
      _activeQuoteMessageId = null;
      _upsertMessage(message.copyWith(media: hydratedMedia));
      _updateMediaForMessage(message.id, hydratedMedia);
    });
    _updateComposerState(pendingAttachments: const [], isUploading: false);
  }

  Future<void> _clearPersistedMediaForRestoredContinuation(
    String messageId,
  ) async {
    await widget.mediaAttachmentRepo?.deleteAttachmentsForMessage(messageId);
  }

  Future<void> _trackRestoredMediaContinuation({
    required _GroupComposerSnapshot snapshot,
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

  bool _hasUploadPendingVoiceAttachment(List<MediaAttachment> attachments) {
    return attachments.any(
      (attachment) =>
          _isAudioAttachment(attachment) &&
          attachment.downloadStatus == 'upload_pending',
    );
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
  }) async {
    final continuation = _restoredVoiceContinuation;
    final mediaAttachmentRepo = widget.mediaAttachmentRepo;
    if (continuation == null || mediaAttachmentRepo == null) {
      return null;
    }
    if (continuation.groupId != widget.group.id ||
        !_sameOptionalMessageId(
          continuation.quotedMessageId,
          quotedMessageId,
        )) {
      _clearRestoredVoiceContinuationTracking();
      return null;
    }

    final message = await widget.msgRepo.getMessage(continuation.messageId);
    final attachments = await mediaAttachmentRepo.getAttachmentsForMessage(
      continuation.messageId,
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

  Future<void> _loadMessages() async {
    var appliedMessages = false;
    try {
      final messages = await widget.msgRepo.getMessagesPage(widget.group.id);
      final historyGapRepair = await widget.historyGapRepairRepo
          ?.getLatestRepairForGroup(widget.group.id);
      if (!mounted) return;

      final mediaMap = await _loadResolvedMediaMap(messages);
      if (!mounted) return;

      setState(() {
        // Apply the same quote-threaded ordering that _upsertMessage uses, so
        // the initial render order matches every subsequent in-place update and
        // no row reshuffles on the first send/receive. (The repository already
        // orders today; this keeps the two paths in lockstep defensively.)
        _messages = orderGroupMessagesForTimeline(messages);
        _mediaMap = mediaMap;
        _initialLoadDone = true;
        _messageLoadErrorText = null;
        _historyGapRepair = historyGapRepair;
      });
      appliedMessages = true;
      // 144 finding: a persisted terminal send_failed bubble must reconstruct
      // its read-only latch on reopen. Re-run after the rows load (the security
      // status may have completed first, before _messages was populated).
      _hydrateTerminalReadOnlyFromState();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _emitNotificationTapTimingIfNeeded();
        _scrollToHighlightedMessage();
      });

      unawaited(_loadReactions(messages));
      unawaited(_downloadPendingMedia(mediaMap));
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
    if (widget.mediaFileManager == null || widget.mediaAttachmentRepo == null) {
      return;
    }
    for (final entry in mediaMap.entries) {
      for (final attachment in entry.value) {
        if (!_shouldRecoverVisibleAttachment(attachment)) {
          continue;
        }

        final retrying = attachment.copyWith(
          clearLocalPath: true,
          downloadStatus: kMediaDownloadStatusDownloading,
        );
        try {
          await widget.mediaAttachmentRepo!.saveAttachment(retrying);
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
                .getAttachmentsForMessage(entry.key);
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

  void _startListening() {
    _messageSubscription = widget.groupMessageListener.groupMessageStream
        .listen(
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
    if (messageId == null || status == null) return;
    _updateLocalMessageStatus(messageId, status);
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

  Future<List<_PreparedGroupMediaUpload>> _prepareDurableGroupMediaUploads({
    required String messageId,
    required List<PendingComposerMedia> mediaToUpload,
  }) async {
    final mediaAttachmentRepo = widget.mediaAttachmentRepo;
    final mediaFileManager = widget.mediaFileManager;
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

    for (final pending in mediaToUpload) {
      final mime = _mimeFromPath(pending.file.path);
      final validation = await GroupMediaMimePolicy.validateFile(
        path: pending.file.path,
        mime: mime,
        mediaType: GroupMediaMimePolicy.mediaTypeForMime(mime),
      );
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
      final blobId = _uuid.v4();
      final durableRelativePath = await mediaFileManager.copyToDurableStorage(
        sourceFilePath: pending.file.path,
        messageId: messageId,
        attachmentId: blobId,
        mime: mime,
      );
      final absoluteDurablePath = await mediaFileManager.resolveStoredPath(
        durableRelativePath,
      );
      final contentHash = await GroupMediaIntegrityPolicy.computeFileSha256Hex(
        absoluteDurablePath,
      );
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
        contentHash: contentHash,
      );
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_CONV_FL_MEDIA_DURABLE_ROW_SAVE',
        details: {
          'messageId': messageId.length > 8
              ? messageId.substring(0, 8)
              : messageId,
          'blobId': blobId.length > 8 ? blobId.substring(0, 8) : blobId,
        },
      );
      await mediaAttachmentRepo.saveAttachment(pendingAttachment);
      preparedUploads.add(
        _PreparedGroupMediaUpload(
          source: pending,
          pendingAttachment: pendingAttachment,
          absoluteDurablePath: absoluteDurablePath,
        ),
      );
    }

    final pendingRows = await mediaAttachmentRepo.getUploadPendingAttachments();
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_CONV_FL_MEDIA_DURABLE_PREP_DONE',
      details: {'pendingCount': pendingRows.length},
    );

    // Let the persisted upload_pending rows settle before any upload callback
    // observes them. This keeps the durable pre-persist contract deterministic
    // in tests and on fast in-memory repositories.
    await Future<void>.delayed(Duration.zero);

    return preparedUploads;
  }

  Future<List<MediaAttachment>?> _uploadPreparedGroupMediaUploads({
    required String messageId,
    required List<_PreparedGroupMediaUpload> preparedUploads,
    required List<String> allowedPeers,
  }) async {
    final mediaAttachmentRepo = widget.mediaAttachmentRepo;
    final mediaFileManager = widget.mediaFileManager;
    if (mediaAttachmentRepo == null || mediaFileManager == null) {
      return null;
    }

    final fileSizes = <String, int>{};
    final totalBytes = preparedUploads.fold<int>(0, (sum, plan) {
      final fileSize = plan.source.budgetBytes;
      fileSizes[plan.pendingAttachment.id] = fileSize;
      return sum + fileSize;
    });

    await _startRelayUploadTracking(totalBytes);
    List<MediaAttachment?> uploadResults;
    try {
      uploadResults = await Future.wait(
        preparedUploads.map((plan) async {
          emitFlowEvent(
            layer: 'FL',
            event: 'GROUP_CONV_FL_MEDIA_UPLOAD_START',
            details: {
              'messageId': messageId.length > 8
                  ? messageId.substring(0, 8)
                  : messageId,
              'blobId': plan.pendingAttachment.id.length > 8
                  ? plan.pendingAttachment.id.substring(0, 8)
                  : plan.pendingAttachment.id,
            },
          );
          await mediaAttachmentRepo.saveAttachment(plan.pendingAttachment);
          _markRelayUploadStarted(plan.pendingAttachment.id);
          try {
            final uploaded = await widget.uploadMediaFn(
              bridge: widget.bridge,
              localFilePath: plan.absoluteDurablePath,
              mime: plan.pendingAttachment.mime,
              recipientPeerId: widget.group.id,
              mediaFileManager: mediaFileManager,
              width: plan.source.width,
              height: plan.source.height,
              durationMs: plan.source.durationMs,
              allowedPeers: allowedPeers,
              blobId: plan.pendingAttachment.id,
            );
            if (uploaded != null) {
              _markRelayUploadCompleted(
                fileSizes[plan.pendingAttachment.id] ?? 0,
              );
            }
            return uploaded;
          } catch (e) {
            emitFlowEvent(
              layer: 'FL',
              event: 'GROUP_CONV_FL_MEDIA_UPLOAD_ERROR',
              details: {'error': e.toString()},
            );
            return null;
          }
        }),
      );
    } finally {
      await _stopRelayUploadTracking();
    }

    if (_activeAttachmentUpload?.cancelRequested ?? false) {
      return const [];
    }

    final completedAttachments = <MediaAttachment>[];
    final failedPlans = <_PreparedGroupMediaUpload>[];

    for (var index = 0; index < uploadResults.length; index++) {
      final plan = preparedUploads[index];
      final uploaded = uploadResults[index];

      if (uploaded == null) {
        failedPlans.add(plan);
        continue;
      }

      final completed = await _buildStableUploadedAttachmentFromPlan(
        messageId: messageId,
        plan: plan,
        uploaded: uploaded,
      );
      await mediaAttachmentRepo.saveAttachment(completed);
      completedAttachments.add(completed);
    }

    if (failedPlans.isNotEmpty) {
      for (final plan in failedPlans) {
        final nextRetryCount =
            (plan.pendingAttachment.uploadRetryCount ?? 0) + 1;
        await mediaAttachmentRepo.saveAttachment(
          plan.pendingAttachment.copyWith(
            downloadStatus: nextRetryCount >= kMaxUploadRetries
                ? 'upload_failed'
                : 'upload_pending',
            uploadRetryCount: nextRetryCount,
          ),
        );
      }
      return null;
    }

    return completedAttachments;
  }

  Future<MediaAttachment> _buildStableUploadedAttachmentFromPlan({
    required String messageId,
    required _PreparedGroupMediaUpload plan,
    required MediaAttachment uploaded,
  }) async {
    final mediaFileManager = widget.mediaFileManager;
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
      contactPeerId: widget.group.id,
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
        contactPeerId: widget.group.id,
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

    final mediaToUpload = List<PendingComposerMedia>.from(_pendingAttachments);
    final hasAttachments = mediaToUpload.isNotEmpty;
    if (text.isEmpty && !hasAttachments) return;
    final draftText = text;
    final quotedMessageId = _activeQuoteMessageId;
    final restoredResolution = await _resolveRestoredMediaContinuationForSend(
      draftText: draftText,
      quotedMessageId: quotedMessageId,
      pendingAttachments: mediaToUpload,
    );
    if (restoredResolution.handled) return;
    if (!_validatePendingGroupMediaDescriptors(mediaToUpload)) {
      return;
    }
    if (!_tryBeginSendFlow()) return;
    final restoredContinuation = restoredResolution.continuation;
    if (restoredContinuation != null) {
      _clearRestoredMediaContinuationTracking();
    }
    final composerSnapshot = _GroupComposerSnapshot(
      draftText: draftText,
      quotedMessageId: quotedMessageId,
      pendingAttachments: List<PendingComposerMedia>.from(_pendingAttachments),
    );

    // 1. Generate IDs upfront for optimistic display
    final messageId = restoredContinuation?.messageId ?? _uuid.v4();
    final now = restoredContinuation?.timestamp ?? DateTime.now().toUtc();

    // 2. Capture and clear pending attachments
    List<MediaAttachment>? optimisticMedia;
    var optimisticDisplayed = false;

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
    }

    _pendingAttachments = [];
    _draftText = '';
    _updateComposerState(
      pendingAttachments: const [],
      isUploading: mediaToUpload.isNotEmpty,
    );
    if (_activeQuoteMessageId != null && mounted) {
      setState(() => _activeQuoteMessageId = null);
    }

    // 3. Create optimistic message and display immediately
    final optimisticMessage = GroupMessage(
      id: messageId,
      groupId: widget.group.id,
      senderPeerId: _ownPeerId!,
      senderUsername: _senderUsername,
      text: text,
      timestamp: now,
      quotedMessageId: quotedMessageId,
      // 210: while the sender is offline the optimistic bubble must show a CLOCK
      // from the very first frame (no 'sending' tick flash). The send result
      // handler re-affirms 'queued_offline' after the awaited send fails.
      status: widget.p2pService.currentState.relayReady
          ? 'sending'
          : GroupMessage.statusQueuedOffline,
      isIncoming: false,
      createdAt: now,
    );

    void showOptimisticMessage() {
      if (!mounted || optimisticDisplayed) return;
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
    final bgTaskId = await _beginBackgroundTaskGuarded();
    try {
      // 5. Upload attachments (if any)
      List<MediaAttachment>? uploadedAttachments;
      if (mediaToUpload.isNotEmpty) {
        _beginActiveAttachmentUpload(
          messageId: messageId,
          composerSnapshot: composerSnapshot,
        );
        if (restoredContinuation != null) {
          await _clearPersistedMediaForRestoredContinuation(messageId);
        }
        final members = await widget.groupRepo.getMembers(widget.group.id);
        final allowedPeers = groupMediaAllowedPeersForMembers(members);

        try {
          if (_supportsDurableGroupMediaUploads) {
            final preparedUploads = await _prepareDurableGroupMediaUploads(
              messageId: messageId,
              mediaToUpload: mediaToUpload,
            );
            await widget.msgRepo.saveMessage(optimisticMessage);
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
            uploadedAttachments = await _uploadPreparedGroupMediaUploads(
              messageId: messageId,
              preparedUploads: preparedUploads,
              allowedPeers: allowedPeers,
            );
            if (await _cancelActiveAttachmentUploadIfRequested()) {
              return;
            }
            if (uploadedAttachments == null) {
              await _restoreComposerSnapshot(composerSnapshot, messageId);
              return;
            }
          } else {
            final optimistic = <MediaAttachment>[];
            for (final m in mediaToUpload) {
              final mime = _mimeFromPath(m.file.path);
              optimistic.add(
                MediaAttachment(
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
                  createdAt: now.toIso8601String(),
                ),
              );
            }
            optimisticMedia = optimistic;
            showOptimisticMessage();

            uploadedAttachments = [];
            var relayTrackingStarted = false;
            for (var index = 0; index < mediaToUpload.length; index++) {
              if (await _cancelActiveAttachmentUploadIfRequested()) {
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
                await _startRelayUploadTracking(remainingBytes);
                relayTrackingStarted = true;
              }
              _markRelayUploadStarted(attachmentId);
              final result = await widget.uploadMediaFn(
                bridge: widget.bridge,
                localFilePath: pending.file.path,
                mime: mime,
                recipientPeerId: widget.group.id,
                mediaFileManager: widget.mediaFileManager,
                width: pending.width,
                height: pending.height,
                durationMs: pending.durationMs,
                allowedPeers: allowedPeers,
                blobId: attachmentId,
              );
              if (result != null) {
                _markRelayUploadCompleted(fileSize);
                final contentHash =
                    result.contentHash ??
                    await GroupMediaIntegrityPolicy.computeFileSha256Hex(
                      pending.file.path,
                    );
                uploadedAttachments.add(
                  result.copyWith(
                    id: attachmentId,
                    messageId: messageId,
                    downloadStatus: 'done',
                    contentHash: contentHash,
                  ),
                );
              } else {
                await _stopRelayUploadTracking();
                await _restoreComposerSnapshot(composerSnapshot, messageId);
                return;
              }
              if (await _cancelActiveAttachmentUploadIfRequested()) {
                return;
              }
            }
            if (await _cancelActiveAttachmentUploadIfRequested()) {
              return;
            }
            await _stopRelayUploadTracking();
            if (mounted) {
              _updateComposerState(isUploading: false);
            }
          }
        } finally {
          _clearActiveAttachmentUpload();
        }
      } else {
        showOptimisticMessage();
      }

      if (await _cancelActiveAttachmentUploadIfRequested()) {
        return;
      }

      final senderDeviceId = _currentSenderDeviceId;
      final (result, message) = await sendGroupMessage(
        bridge: widget.bridge,
        groupRepo: widget.groupRepo,
        msgRepo: widget.msgRepo,
        groupId: widget.group.id,
        text: text,
        senderPeerId: _ownPeerId!,
        senderPublicKey: _senderPublicKey,
        senderPrivateKey: _senderPrivateKey,
        senderUsername: _senderUsername,
        messageId: messageId,
        timestamp: now,
        quotedMessageId: quotedMessageId,
        senderDeviceId: senderDeviceId,
        senderTransportPeerId: senderDeviceId,
        mediaAttachments: uploadedAttachments,
        mediaAttachmentRepo: widget.mediaAttachmentRepo,
        inviteDeliveryAttemptRepo: widget.inviteDeliveryAttemptRepo,
      );

      if ((result == SendGroupMessageResult.success ||
              result == SendGroupMessageResult.successNoPeers) &&
          message != null) {
        // Resolve uploaded media paths for display
        List<MediaAttachment>? displayMedia;
        if (uploadedAttachments != null && widget.mediaFileManager != null) {
          displayMedia = [];
          for (final a in uploadedAttachments) {
            if (a.localPath != null) {
              final absPath = await widget.mediaFileManager!.resolveStoredPath(
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
        if (_supportsDurableGroupMediaUploads && mediaToUpload.isNotEmpty) {
          try {
            await widget.mediaFileManager?.deletePendingUploadDir(messageId);
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
          await widget.msgRepo.saveMessage(failedMessage);
        } catch (_) {}
        _updateLocalMessageStatus(messageId, GroupMessage.statusSendFailed);
        if (result == SendGroupMessageResult.groupDissolved) {
          // Refreshes the rest of the group UI. The read-only override below is
          // what actually flips the banner: the row is NOT marked dissolved in
          // the empty-membership case, so a membership refresh fails open.
          await _refreshVisibleGroup();
        }
        _setTerminalSendReadOnly(_terminalReadOnlyForSendResult(result));
      } else if (!widget.p2pService.currentState.relayReady &&
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
        await _endBackgroundTaskGuarded(bgTaskId);
      } finally {
        _endSendFlow();
      }
    }
  }

  void _onDraftChanged(String text) {
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

    final persisted = await mediaAttachmentRepo.getAttachmentsForMessage(
      messageId,
    );
    final fallback = _mediaMap[messageId] ?? persisted;
    final target = persisted
        .where((attachment) => attachment.id == attachmentId)
        .firstOrNull;
    if (target == null) {
      _showFloatingSnackBar(
        AppLocalizations.of(context)!.media_unavailable_now,
        backgroundColor: Colors.red[700],
      );
      return;
    }

    await _deleteUnsafeLocalMediaFile(target);

    final retrying = target.copyWith(
      clearLocalPath: true,
      downloadStatus: kMediaDownloadStatusDownloading,
    );
    await mediaAttachmentRepo.saveAttachment(retrying);
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

  Future<void> _deleteUnsafeLocalMediaFile(MediaAttachment attachment) async {
    final localPath = attachment.localPath;
    final mediaFileManager = widget.mediaFileManager;
    if (localPath == null || mediaFileManager == null) return;
    if (_isPendingUploadPath(localPath)) return;

    try {
      final absolutePath = await mediaFileManager.resolveStoredPath(localPath);
      if (_isPendingUploadPath(absolutePath)) return;
      final file = File(absolutePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
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
    );
    if (persistedMedia.any(
      (attachment) => attachment.downloadStatus == 'upload_pending',
    )) {
      if (_hasUploadPendingVoiceAttachment(persistedMedia)) {
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
            inviteDeliveryAttemptRepo: widget.inviteDeliveryAttemptRepo,
          );
        } catch (e) {
          emitFlowEvent(
            layer: 'FL',
            event: 'GROUP_CONV_FL_VOICE_UPLOAD_PENDING_RETRY_ERROR',
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
        // 149: the upload-pending / failed state is conveyed inline by the
        // MediaGridCell placeholder — the redundant retry-failed snackbar is
        // dropped.
        return;
      }
      await _refreshMessageWithHydratedMedia(
        messageId,
        fallbackMedia: fallbackMedia,
      );
      // 149: the upload-pending state is conveyed inline by the MediaGridCell
      // upload-pending placeholder — the redundant snackbar is dropped.
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
        inviteDeliveryAttemptRepo: widget.inviteDeliveryAttemptRepo,
      );

      await _refreshMessageWithHydratedMedia(messageId);

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
        .getAttachmentsForMessage(messageId);
    final storedPaths = storedAttachments.map(
      (attachment) => attachment.localPath,
    );

    await mediaAttachmentRepo.markUploadPendingAttachmentsFailedForMessage(
      messageId,
    );
    await mediaFileManager.deleteOwnedPendingUploadFilesForMessage(
      messageId: messageId,
      storedPaths: storedPaths,
    );
    await mediaAttachmentRepo.deleteAttachmentsForMessage(messageId);
    await widget.msgRepo.deleteMessage(messageId);

    _removeLocalMessage(messageId);
  }

  Future<void> _cleanupRestoredComposerRetryState(String messageId) async {
    try {
      await widget.mediaAttachmentRepo
          ?.markUploadPendingAttachmentsFailedForMessage(messageId);
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
    _pendingAttachments = [];
    _clearRestoredMediaContinuationTracking();
    if (mounted) {
      _updateComposerState(pendingAttachments: const [], isUploading: false);
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
    _GroupComposerSnapshot snapshot,
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
    _pendingAttachments = List<PendingComposerMedia>.from(
      snapshot.pendingAttachments,
    );
    if (mounted) {
      _updateComposerState(
        pendingAttachments: _pendingAttachmentFiles(),
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

  Future<void> _restoreComposerSnapshotWithoutFailure(
    _GroupComposerSnapshot snapshot,
    String messageId, {
    String? snackText,
    bool showSnackBar = false,
  }) async {
    if (mounted) {
      setState(() {
        _draftText = snapshot.draftText;
        _pendingAttachments = List<PendingComposerMedia>.from(
          snapshot.pendingAttachments,
        );
        _activeQuoteMessageId = snapshot.quotedMessageId;
        _removeLocalMessage(messageId);
      });
      _updateComposerState(
        pendingAttachments: _pendingAttachmentFiles(),
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
    _updateLocalMessageStatus(messageId, GroupMessage.statusQueuedOffline);
    await _persistMessageStatus(messageId, GroupMessage.statusQueuedOffline);
  }

  /// 210: the offline queued-send informational snackbar. Mirrors the 1:1
  /// `conversation_wired` offline copy EXACTLY — a wifi-off glyph + the
  /// hardcoded "Will send when you're back online" const on the slate/blueGrey
  /// floating surface (informational/self-healing tone, NOT error-red). The copy
  /// is a hardcoded const to match 1:1; l10n is deferred debt for both paths.
  void _showOfflineQueuedSnackBar() {
    if (!mounted) return;
    const senderOfflineCopy = "Will send when you're back online";
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.wifi_off_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                senderOfflineCopy,
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
    final attachments = await mediaRepo.getAttachmentsForMessage(messageId);
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
    final details = <String, Object?>{
      if (storedPath != null) 'storedPath': storedPath,
      if (storedPath != null) 'storedPathKind': _groupMediaPathKind(storedPath),
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
      await widget.mediaAttachmentRepo?.saveAttachment(quarantined);
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
      await widget.mediaAttachmentRepo?.saveAttachment(pending);
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
        GroupMediaSizePolicy.validateAttachments(
          [attachment],
          perMediaLimitBytes: kGroupMediaPerAttachmentLimitBytes,
        ).isValid &&
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
    final latestMessage =
        await widget.msgRepo.getMessage(message.id) ?? message;

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
    final shownMedia =
        _mediaMap[latestMessage.id] ?? const <MediaAttachment>[];
    final shouldResolveMedia =
        !alreadyShown || message.media.isNotEmpty || shownMedia.isNotEmpty;
    final media = shouldResolveMedia
        ? await _loadResolvedAttachmentsForMessage(latestMessage.id)
        : shownMedia;
    if (!mounted) return;

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
      final remaining = _maxAttachments - _pendingAttachments.length;
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
      if (_pendingAttachments.length >= _maxAttachments) return;
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
      if (_pendingAttachments.length >= _maxAttachments) return;
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
    if (index < 0 || index >= _pendingAttachments.length) return;
    final updated = List<PendingComposerMedia>.from(_pendingAttachments);
    updated.removeAt(index);
    _pendingAttachments = updated;
    _clearRestoredMediaContinuationTracking();
    _updateComposerState(pendingAttachments: _pendingAttachmentFiles());
  }

  void _upsertMessage(GroupMessage message) {
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
    final updated = List<GroupMessage>.from(_messages);
    updated[idx] = updated[idx].copyWith(status: status);
    if (mounted) {
      setState(() => _messages = updated);
    } else {
      _messages = updated;
    }
  }

  void _removeLocalMessage(String messageId) {
    final nextMessages = _messages
        .where((message) => message.id != messageId)
        .toList();
    final nextMedia = Map<String, List<MediaAttachment>>.from(_mediaMap);
    nextMedia.remove(messageId);
    if (mounted) {
      setState(() {
        _messages = nextMessages;
        _mediaMap = nextMedia;
      });
    } else {
      _messages = nextMessages;
      _mediaMap = nextMedia;
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

  List<File> _pendingAttachmentFiles() => _pendingAttachments
      .map((attachment) => attachment.file)
      .toList(growable: false);

  void _updateComposerState({
    List<File>? pendingAttachments,
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
    final current = _composerState.value;
    // 149: re-derive the size/GIF reject set from the LIVE pending list whenever
    // the attachment list changes (pick/remove), so the inline reject-chip +
    // Send-disable always track the current attachments. Size/GIF only — the
    // unsupported-MIME hard reject stays a SEND-time snackbar, not a chip.
    var nextInvalidIndices = invalidAttachmentIndices;
    var nextInvalidReasons = invalidAttachmentReasons;
    bool? nextHasTotalSizeOverflow;
    if (pendingAttachments != null && invalidAttachmentIndices == null) {
      if (pendingAttachments.isEmpty) {
        nextInvalidIndices = const <int>{};
        nextInvalidReasons = const <int, String>{};
        nextHasTotalSizeOverflow = false;
      } else {
        final rejections = collectPendingMediaSizeRejections(
          _pendingAttachments,
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
        nextHasTotalSizeOverflow = nextInvalidIndices.isEmpty &&
            pendingMediaTotalSizeOverflow(_pendingAttachments);
      }
    }
    final next = current.copyWith(
      pendingAttachments: pendingAttachments,
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
    if (_composerStateEquals(current, next)) return;
    _composerState.value = next;
  }

  bool _composerStateEquals(
    ConversationComposerViewState a,
    ConversationComposerViewState b,
  ) {
    return a.isUploading == b.isUploading &&
        a.isProcessing == b.isProcessing &&
        a.processingProgress == b.processingProgress &&
        a.processingCurrent == b.processingCurrent &&
        a.processingTotal == b.processingTotal &&
        a.recordingState == b.recordingState &&
        a.recordingDuration == b.recordingDuration &&
        listEquals(a.amplitudeValues, b.amplitudeValues) &&
        setEquals(a.invalidAttachmentIndices, b.invalidAttachmentIndices) &&
        mapEquals(a.invalidAttachmentReasons, b.invalidAttachmentReasons) &&
        a.hasTotalSizeOverflow == b.hasTotalSizeOverflow &&
        _fileListsEqual(a.pendingAttachments, b.pendingAttachments);
  }

  bool _fileListsEqual(List<File> a, List<File> b) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (a[index].path != b[index].path) return false;
    }
    return true;
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
    final targetId = widget.initialHighlightedMessageId;
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
    if (recorder == null || _composerViewState.recordingState.isActive) {
      return;
    }

    _pendingRecorderAbort = false;
    _updateComposerState(
      recordingState: VoiceRecordingState.arming,
      recordingDuration: Duration.zero,
      amplitudeValues: const [],
    );

    final status = await widget.micPermissionGateway.request();
    if (!mounted || _pendingRecorderAbort) {
      _updateComposerState(
        recordingState: VoiceRecordingState.idle,
        recordingDuration: Duration.zero,
        amplitudeValues: const [],
      );
      return;
    }

    if (status != MicPermissionStatus.granted) {
      if (mounted) {
        // permanentlyDenied/restricted = the OS will no longer re-prompt
        // in-app, so the only recovery is the system Settings deep-link (152).
        // Shared helper with the 1:1 screen so neither can drift back to a
        // dead-end toast. A first plain `denied` just resets.
        if (status == MicPermissionStatus.permanentlyDenied) {
          await showMicPermissionDeniedPrompt(
            context,
            gateway: widget.micPermissionGateway,
          );
        }
        if (mounted) {
          _updateComposerState(
            recordingState: VoiceRecordingState.idle,
            recordingDuration: Duration.zero,
            amplitudeValues: const [],
          );
        }
      }
      return;
    }

    if (_pendingRecorderAbort ||
        _composerViewState.recordingState == VoiceRecordingState.stopping) {
      _updateComposerState(
        recordingState: VoiceRecordingState.idle,
        recordingDuration: Duration.zero,
        amplitudeValues: const [],
      );
      return;
    }

    try {
      await recorder.start(outputPath: '');
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_CONV_FL_RECORD_START_ERROR',
        details: {'error': e.toString()},
      );
      _updateComposerState(
        recordingState: VoiceRecordingState.idle,
        recordingDuration: Duration.zero,
        amplitudeValues: const [],
      );
      return;
    }

    if (!mounted ||
        _pendingRecorderAbort ||
        _composerViewState.recordingState == VoiceRecordingState.stopping) {
      await recorder.cancel();
      if (mounted) {
        _pendingRecorderAbort = false;
        _updateComposerState(
          recordingState: VoiceRecordingState.idle,
          recordingDuration: Duration.zero,
          amplitudeValues: const [],
        );
      }
      return;
    }

    recorder.onAutoStopped = _onRecorderAutoStopped;
    _durationSub = recorder.durationStream.listen((d) {
      if (mounted) {
        _updateComposerState(recordingDuration: d);
      }
    });

    _amplitudeBuffer.reset();
    _waveformSamples = [];
    _amplitudeSub = recorder.amplitudeStream.listen((value) {
      if (mounted) {
        _amplitudeBuffer.push(value);
        _waveformSamples.add(value);
        _updateComposerState(amplitudeValues: _amplitudeBuffer.values);
      }
    });

    if (mounted) {
      _updateComposerState(
        recordingState: VoiceRecordingState.recording,
        recordingDuration: Duration.zero,
        amplitudeValues: _amplitudeBuffer.values,
      );
    }
  }

  Future<void> _onRecordStop() async {
    if (!_canWrite) return;
    final recorder = widget.audioRecorderService;
    final mediaAttachmentRepo = widget.mediaAttachmentRepo;
    final mediaFileManager = widget.mediaFileManager;
    if (recorder == null ||
        mediaAttachmentRepo == null ||
        mediaFileManager == null ||
        !_composerViewState.recordingState.isActive) {
      return;
    }

    if (_composerViewState.recordingState == VoiceRecordingState.arming) {
      _pendingRecorderAbort = true;
      _updateComposerState(recordingState: VoiceRecordingState.stopping);
      return;
    }
    if (!_tryBeginSendFlow()) return;

    try {
      recorder.onAutoStopped = null;
      _updateComposerState(recordingState: VoiceRecordingState.stopping);
      final quotedMessageId = _activeQuoteMessageId;

      final durationSub = _durationSub;
      _durationSub = null;
      if (durationSub != null) {
        unawaited(durationSub.cancel());
      }
      final amplitudeSub = _amplitudeSub;
      _amplitudeSub = null;
      if (amplitudeSub != null) {
        unawaited(amplitudeSub.cancel());
      }
      _amplitudeBuffer.reset();

      final waveform = downsampleWaveform(_waveformSamples, 50);
      _waveformSamples = [];

      final recording = await recorder.stop();

      if (mounted) {
        _pendingRecorderAbort = false;
        _updateComposerState(
          recordingState: VoiceRecordingState.idle,
          recordingDuration: Duration.zero,
          amplitudeValues: const [],
        );
      }

      if (recording == null || _ownPeerId == null) return;

      if (quotedMessageId != null && mounted) {
        setState(() => _activeQuoteMessageId = null);
      }

      final voiceContinuation =
          await _resolveRestoredVoiceContinuationForRecordStop(
            quotedMessageId: quotedMessageId,
          );
      final messageId = voiceContinuation?.messageId ?? _uuid.v4();
      final attachmentId = _uuid.v4();
      final now = voiceContinuation?.timestamp ?? DateTime.now().toUtc();
      final optimisticMessage = GroupMessage(
        id: messageId,
        groupId: widget.group.id,
        senderPeerId: _ownPeerId!,
        senderUsername: _senderUsername,
        text: '',
        timestamp: now,
        quotedMessageId: quotedMessageId,
        // 210: same offline-first clock as the text path (voice is a separate
        // send surface).
        status: widget.p2pService.currentState.relayReady
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
        absoluteDurablePath = await mediaFileManager.resolveStoredPath(
          durableRelativePath,
        );
        final contentHash =
            await GroupMediaIntegrityPolicy.computeFileSha256Hex(
              absoluteDurablePath,
            );
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
          contentHash: contentHash,
        );
        await mediaAttachmentRepo.saveAttachment(pendingAttachment);
        await widget.msgRepo.saveMessage(optimisticMessage);
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

      final bgTaskId = await _beginBackgroundTaskGuarded();
      try {
        final members = await widget.groupRepo.getMembers(widget.group.id);
        final allowedPeers = groupMediaAllowedPeersForMembers(members);

        _updateComposerState(isUploading: true);
        await _startRelayUploadTracking(recording.sizeBytes);
        _markRelayUploadStarted(attachmentId);

        final voiceAttachment = await widget.uploadMediaFn(
          bridge: widget.bridge,
          localFilePath: durableAbsolutePath,
          mime: recording.mime,
          recipientPeerId: widget.group.id,
          mediaFileManager: mediaFileManager,
          durationMs: recording.durationMs,
          waveform: waveform,
          allowedPeers: allowedPeers,
          blobId: attachmentId,
        );

        if (voiceAttachment == null) {
          await _stopRelayUploadTracking();
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

        final stableVoiceAttachment = await _buildStableVoiceAttachment(
          pendingAttachment: durablePendingAttachment,
          uploaded: voiceAttachment,
          absoluteDurablePath: durableAbsolutePath,
          waveform: waveform,
        );
        if (voiceContinuation != null) {
          final staleAttachments = await mediaAttachmentRepo
              .getAttachmentsForMessage(messageId);
          for (final attachment in staleAttachments) {
            await _deleteUnsafeLocalMediaFile(attachment);
          }
          await mediaAttachmentRepo.deleteAttachmentsForMessage(messageId);
        }
        await mediaAttachmentRepo.saveAttachment(stableVoiceAttachment);
        _markRelayUploadCompleted(recording.sizeBytes);
        await _stopRelayUploadTracking();

        if (mounted) {
          _updateComposerState(isUploading: false);
        }

        final senderDeviceId = _currentSenderDeviceId;
        final (result, message) = await sendGroupMessage(
          bridge: widget.bridge,
          groupRepo: widget.groupRepo,
          msgRepo: widget.msgRepo,
          groupId: widget.group.id,
          text: '',
          senderPeerId: _ownPeerId!,
          senderPublicKey: _senderPublicKey,
          senderPrivateKey: _senderPrivateKey,
          senderUsername: _senderUsername,
          messageId: messageId,
          timestamp: now,
          quotedMessageId: quotedMessageId,
          senderDeviceId: senderDeviceId,
          senderTransportPeerId: senderDeviceId,
          mediaAttachments: [stableVoiceAttachment],
          mediaAttachmentRepo: mediaAttachmentRepo,
          inviteDeliveryAttemptRepo: widget.inviteDeliveryAttemptRepo,
        );

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
          } else if (!widget.p2pService.currentState.relayReady &&
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
        await _stopRelayUploadTracking();
        await _endBackgroundTaskGuarded(bgTaskId);
      }
    } finally {
      _endSendFlow();
    }
  }

  Future<void> _cleanupUnsentVoiceArtifacts({
    required String messageId,
    required MediaAttachmentRepository mediaAttachmentRepo,
    required MediaFileManager mediaFileManager,
  }) async {
    if (mounted) {
      _removeLocalMessage(messageId);
    }
    try {
      await mediaAttachmentRepo.deleteAttachmentsForMessage(messageId);
    } catch (_) {}
    try {
      await mediaFileManager.deletePendingUploadDir(messageId);
    } catch (_) {}
    try {
      await widget.msgRepo.deleteMessage(messageId);
    } catch (_) {}
  }

  Future<MediaAttachment> _buildStableVoiceAttachment({
    required MediaAttachment pendingAttachment,
    required MediaAttachment uploaded,
    required String absoluteDurablePath,
    required List<double> waveform,
  }) async {
    final mediaFileManager = widget.mediaFileManager;
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
      contactPeerId: widget.group.id,
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
        contactPeerId: widget.group.id,
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

    if (quoted.text.isNotEmpty) {
      return (quoted.text, false);
    }

    final quotedMedia = _mediaMap[quoted.id] ?? quoted.media;
    if (quotedMedia.isNotEmpty) {
      return (mediaPreviewText(quotedMedia), false);
    }

    return (null, true);
  }

  Future<void> _onRecordCancel() async {
    if (!_canWrite) return;
    final recorder = widget.audioRecorderService;
    if (recorder == null || !_composerViewState.recordingState.isActive) {
      return;
    }

    if (_composerViewState.recordingState == VoiceRecordingState.arming) {
      _pendingRecorderAbort = true;
      _updateComposerState(recordingState: VoiceRecordingState.stopping);
      return;
    }

    recorder.onAutoStopped = null;
    _updateComposerState(recordingState: VoiceRecordingState.stopping);
    await _durationSub?.cancel();
    _durationSub = null;
    await _amplitudeSub?.cancel();
    _amplitudeSub = null;
    _amplitudeBuffer.reset();
    _waveformSamples = [];

    await recorder.cancel();

    if (mounted) {
      _pendingRecorderAbort = false;
      _updateComposerState(
        recordingState: VoiceRecordingState.idle,
        recordingDuration: Duration.zero,
        amplitudeValues: const [],
      );
    }
  }

  void _onRecorderAutoStopped(AudioRecording? recording) {
    // The recorder stopped itself at the max recording duration without any
    // user gesture; resync the composer. Auto-send is deliberately out of
    // scope — the result is discarded like a too-short recording.
    widget.audioRecorderService?.onAutoStopped = null;
    _durationSub?.cancel();
    _durationSub = null;
    _amplitudeSub?.cancel();
    _amplitudeSub = null;
    _amplitudeBuffer.reset();
    _waveformSamples = [];
    if (mounted) {
      _pendingRecorderAbort = false;
      _updateComposerState(
        recordingState: VoiceRecordingState.idle,
        recordingDuration: Duration.zero,
        amplitudeValues: const [],
      );
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_CONV_FL_RECORD_AUTO_STOPPED',
      details: {'tooShort': recording == null},
    );
  }

  /// Cancels an in-flight recording when the user loses write access or the
  /// visible group changes. The record handlers no-op once [_canWrite] is
  /// false (and the screen nulls them out), so without this an active
  /// recorder would be stranded until auto-stop or dispose.
  void _forceCancelActiveRecording() {
    final recorder = widget.audioRecorderService;
    if (recorder == null || !_composerViewState.recordingState.isActive) {
      return;
    }

    if (_composerViewState.recordingState == VoiceRecordingState.arming) {
      // start() has not finished yet — let its abort path clean up.
      _pendingRecorderAbort = true;
      _updateComposerState(recordingState: VoiceRecordingState.stopping);
      return;
    }

    // Only touch the shared recorder if this surface still owns the live
    // session: another surface's start() may have force-stopped it already,
    // leaving our composer state stale — cancelling then would kill that
    // surface's recording.
    // Tear-offs of the same method are ==, never identical.
    final ownsSession = recorder.onAutoStopped == _onRecorderAutoStopped;
    if (ownsSession) {
      recorder.onAutoStopped = null;
    }
    unawaited(_durationSub?.cancel());
    _durationSub = null;
    unawaited(_amplitudeSub?.cancel());
    _amplitudeSub = null;
    _amplitudeBuffer.reset();
    _waveformSamples = [];
    _pendingRecorderAbort = false;
    if (ownsSession) {
      unawaited(recorder.cancel());
    }
    _updateComposerState(
      recordingState: VoiceRecordingState.idle,
      recordingDuration: Duration.zero,
      amplitudeValues: const [],
    );
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_CONV_FL_RECORD_FORCE_CANCELLED',
      details: {'ownedSession': ownsSession},
    );
  }

  // -------------------------------------------------------------------------
  // Media tap (full screen viewer)
  // -------------------------------------------------------------------------

  void _onMediaTap(String messageId, int index) {
    final attachments = _mediaMap[messageId];
    if (attachments == null) return;

    final visual = attachments
        .where((a) => a.mediaType == 'image' || a.mediaType == 'video')
        .toList();
    if (index < visual.length &&
        GroupMediaIntegrityPolicy.canDisplayVerifiedGroupMedia(visual[index])) {
      final allPaths = visual
          .where(GroupMediaIntegrityPolicy.canDisplayVerifiedGroupMedia)
          .map((a) => a.localPath!)
          .toList();
      if (allPaths.isEmpty) return;
      final tappedPath = visual[index].localPath!;
      final startIndex = allPaths
          .indexOf(tappedPath)
          .clamp(0, allPaths.length - 1)
          .toInt();

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => FullScreenImageViewer(
            localPath: tappedPath,
            allPaths: allPaths,
            initialIndex: startIndex,
          ),
        ),
      );
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

  void _onInfo() {
    Navigator.of(context)
        .push(
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
            ),
          ),
        )
        .then((_) {
          unawaited(_refreshAfterInfoRoute());
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
    try {
      final attachments =
          await widget.mediaAttachmentRepo?.getAttachmentsForMessage(
            messageId,
          ) ??
          const <MediaAttachment>[];
      for (final attachment in attachments) {
        await _deleteUnsafeLocalMediaFile(attachment);
      }
    } catch (_) {}
    try {
      await widget.mediaAttachmentRepo?.deleteAttachmentsForMessage(messageId);
    } catch (_) {}
    try {
      await widget.mediaFileManager?.deletePendingUploadDir(messageId);
    } catch (_) {}
    try {
      await widget.msgRepo.deleteMessage(messageId);
    } catch (_) {}
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
    return _canWriteForSnapshot(
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
      _terminalSendReadOnly == _TerminalReadOnly.none &&
      _canWriteForGroup(_group);

  bool get _canMutateReactions =>
      // 144 finding: a terminal send/reaction read-only latch must also disable
      // the long-press reaction picker (mirrors _canWrite). Otherwise the banner
      // reads read-only while reactions stay tappable, and each tap re-hits the
      // terminal result and silently reverts. Rides the F1 self-heal release.
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

  Future<void> _refreshAfterInfoRoute() async {
    await _refreshVisibleGroup();
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
    final messageIds = messages.map((m) => m.id).toList();
    if (messageIds.isEmpty) return;

    final reactionsByMessage = await loadReactionsForConversation(
      reactionRepo: widget.reactionRepo!,
      messageIds: messageIds,
    );
    if (!mounted) return;

    setState(() {
      _reactions = {..._reactions, ...reactionsByMessage};
    });
  }

  void _startListeningForReactions() {
    _reactionSubscription = widget
        .groupMessageListener
        .groupReactionChangeStream
        .listen(_onIncomingReactionChange);
  }

  void _onIncomingReactionChange(ReactionChange change) {
    if (!mounted) return;
    setState(() {
      final list = List<MessageReaction>.from(
        _reactions[change.messageId] ?? [],
      );

      if (change.type == ReactionChangeType.removed) {
        list.removeWhere((r) => r.senderPeerId == change.senderPeerId);
      } else if (change.reaction != null) {
        // Replace existing from same sender or add
        list.removeWhere((r) => r.senderPeerId == change.senderPeerId);
        list.add(change.reaction!);
      }

      _reactions = {..._reactions, change.messageId: list};
    });
  }

  Future<void> _onReactionSelected(String messageId, String emoji) async {
    if (!_canMutateReactions) return;
    if (_ownPeerId == null) return;

    final previousReactions = List<MessageReaction>.from(
      _reactions[messageId] ?? const <MessageReaction>[],
    );

    // Check if we already have a reaction with this emoji — toggle off
    final existing = previousReactions.where(
      (r) => r.senderPeerId == _ownPeerId && r.emoji == emoji,
    );

    if (existing.isNotEmpty) {
      // Optimistic remove
      setState(() {
        final list = List<MessageReaction>.from(_reactions[messageId] ?? []);
        list.removeWhere((r) => r.senderPeerId == _ownPeerId);
        _reactions = {..._reactions, messageId: list};
      });

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
        _restoreReactionState(messageId, previousReactions);
        return;
      }
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
    setState(() {
      final list = List<MessageReaction>.from(_reactions[messageId] ?? []);
      list.removeWhere((r) => r.senderPeerId == _ownPeerId);
      list.add(tempReaction);
      _reactions = {..._reactions, messageId: list};
    });

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
      _restoreReactionState(messageId, previousReactions);
      return;
    }

    final confirmedReaction = reaction;
    // queuedForRetry keeps the emoji: swap the temp for the persisted reaction
    // just like success. The reaction is durably staged and will be re-driven
    // by the retry driver (INV-R1) instead of silently reverted.
    if ((result == SendGroupReactionResult.success ||
            result == SendGroupReactionResult.queuedForRetry) &&
        confirmedReaction != null) {
      if (!mounted) return;
      setState(() {
        final list = List<MessageReaction>.from(_reactions[messageId] ?? []);
        list.removeWhere((r) => r.id == '' && r.senderPeerId == _ownPeerId);
        list.add(confirmedReaction);
        _reactions = {..._reactions, messageId: list};
      });
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
    setState(() {
      _reactions = {..._reactions, messageId: previousReactions};
    });
  }

  Future<void> _restoreReactionStateAfterDissolve(
    String messageId,
    List<MessageReaction> previousReactions,
  ) async {
    if (mounted) {
      setState(() {
        _reactions = {..._reactions, messageId: previousReactions};
      });
    }
    await _refreshVisibleGroup();
    // 144 INV-5: the durable read-only banner is the terminal feedback now, not
    // a transient snackbar. The override flips the banner even when the group
    // row has not been marked dissolved locally yet.
    _setTerminalSendReadOnly(_TerminalReadOnly.dissolved);
  }

  Future<void> _onReactionTap(String messageId, String emoji) async {
    final allReactions = _reactions[messageId] ?? const <MessageReaction>[];
    if (allReactions.isEmpty) return;

    final members = await widget.groupRepo.getMembers(widget.group.id);
    final usernameHintsByPeerId = await loadGroupReactionUsernameHints(
      peerIds: allReactions.map((reaction) => reaction.senderPeerId),
      contactRepo: widget.contactRepo,
      groupId: widget.group.id,
      msgRepo: widget.msgRepo,
    );
    if (!mounted) return;

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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.groupConversationTracker?.clearIfActive(_activeGroupConversationKey);
    _messageSubscription?.cancel();
    _outgoingLocalMessageChangeSubscription?.cancel();
    _removedSubscription?.cancel();
    _reactionSubscription?.cancel();
    _mediaUploadProgressSubscription?.cancel();
    _durationSub?.cancel();
    _amplitudeSub?.cancel();
    if (_isRecording) {
      final recorder = widget.audioRecorderService;
      // Only cancel a session this surface still owns — our recording state
      // can be stale after another surface displaced the shared recorder.
      if (recorder != null &&
          recorder.onAutoStopped == _onRecorderAutoStopped) {
        recorder.onAutoStopped = null;
        recorder.cancel();
      }
    }
    _scrollController.dispose();
    _composerState.dispose();
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
            uploadProgress: _uploadProgressViewState,
            securityStatus: _securityStatus,
            onCancelUpload:
                _activeAttachmentUpload == null ||
                    _activeAttachmentUpload!.cancelRequested
                ? null
                : _requestCancelActiveAttachmentUpload,
            initialLoadDone: _initialLoadDone,
            isRecovering: recoveryDepth > 0,
            messageLoadErrorText: _messageLoadErrorText,
            onRetryMessageLoad: _retryMessageLoad,
            scrollController: _scrollController,
            highlightedMessageId: widget.initialHighlightedMessageId,
            highlightAnchorKey: _highlightAnchorKey,
            mediaMap: _mediaMap,
            composerStateListenable: _composerState,
            onRemoveAttachment: _removeAttachment,
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
            recordingState: _composerViewState.recordingState,
            onMediaTap: _onMediaTap,
            reactions: _reactions,
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

class _GroupComposerSnapshot {
  final String draftText;
  final String? quotedMessageId;
  final List<PendingComposerMedia> pendingAttachments;

  const _GroupComposerSnapshot({
    required this.draftText,
    required this.quotedMessageId,
    required this.pendingAttachments,
  });
}

class _GroupActiveAttachmentUpload {
  final String messageId;
  final _GroupComposerSnapshot composerSnapshot;
  final bool cancelRequested;

  const _GroupActiveAttachmentUpload({
    required this.messageId,
    required this.composerSnapshot,
    this.cancelRequested = false,
  });

  _GroupActiveAttachmentUpload copyWith({bool? cancelRequested}) {
    return _GroupActiveAttachmentUpload(
      messageId: messageId,
      composerSnapshot: composerSnapshot,
      cancelRequested: cancelRequested ?? this.cancelRequested,
    );
  }
}
