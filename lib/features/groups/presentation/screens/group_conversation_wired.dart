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
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/media/downsample_waveform.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/group_media_mime_policy.dart';
import 'package:flutter_app/core/media/group_media_size_policy.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_picker.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/pending_composer_media.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/utils/notification_tap_timing.dart';
import 'package:flutter_app/core/constants/retry_constants.dart';
import 'package:flutter_app/core/constants/media_constants.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/download_media_use_case.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
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
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/application/send_group_reaction_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_member_identity_safety.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_history_gap_repair.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_history_gap_repair_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_reaction_replay_outbox_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/groups/domain/utils/group_message_ordering.dart';
import 'package:flutter_app/features/groups/presentation/group_backlog_retention_notice.dart';
import 'package:flutter_app/features/groups/presentation/group_security_status_view_state.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_screen.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_info_wired.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_reaction_details_sheet.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_app/features/settings/domain/models/image_quality_preference.dart';
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

/// Wired widget connecting GroupConversationScreen to business logic.
class GroupConversationWired extends StatefulWidget {
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

class _GroupConversationWiredState extends State<GroupConversationWired>
    with WidgetsBindingObserver {
  static const _maxAttachments = 10;
  static const _liveEdgeTolerance = 32.0;
  static const _messageLoadErrorCopy = "Couldn't load messages";
  static final MediaPicker _defaultMediaPicker = SystemMediaPicker();

  late GroupModel _group;
  List<GroupMessage> _messages = [];
  Map<String, GroupMember> _membersByPeerId = const {};
  String? _ownPeerId;
  String _senderUsername = '';
  String _senderPublicKey = '';
  String _senderPrivateKey = '';
  StreamSubscription<GroupMessage>? _messageSubscription;
  StreamSubscription<String>? _removedSubscription;
  final ScrollController _scrollController = ScrollController();
  bool _initialLoadDone = false;
  bool _isSending = false;
  String? _activeQuoteMessageId;
  String _draftText = '';
  String? _messageLoadErrorText;
  GroupSecurityStatusViewState? _securityStatus;
  GroupHistoryGapRepair? _historyGapRepair;
  bool _isCurrentUserActiveMember = true;
  bool _hasCurrentSendKey = true;
  bool _isLifecycleResumed = true;

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
      snackText: 'Upload cancelled.',
      showSnackBar: true,
    );
    return true;
  }

  Future<bool> _confirmLeaveWhileUploadActive() async {
    if (!_isTrackingRelayUpload || !mounted) return true;
    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave conversation?'),
        content: const Text(
          'An upload is in progress. Leaving may interrupt it. Are you sure?',
        ),
        actions: [
          TextButton(
            key: const ValueKey('upload-leave-stay'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Stay'),
          ),
          FilledButton(
            key: const ValueKey('upload-leave-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Leave'),
          ),
        ],
      ),
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
    if (oldCanWrite && !_canWrite && _activeQuoteMessageId != null) {
      _activeQuoteMessageId = null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isLifecycleResumed = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshVisibleGroup());
      unawaited(_markVisibleReadIfAllowed());
    }
  }

  void _resetForGroupChange(GroupConversationWired oldWidget) {
    widget.groupConversationTracker?.clearIfActive(
      'group:${oldWidget.group.id}',
    );
    widget.groupConversationTracker?.setActive(_activeGroupConversationKey);
    unawaited(_messageSubscription?.cancel());
    unawaited(_removedSubscription?.cancel());
    unawaited(_reactionSubscription?.cancel());
    _messageSubscription = null;
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
    _initialLoadDone = false;
    _activeQuoteMessageId = null;
    _draftText = widget.initialText ?? '';
    _pendingAttachments = [];
    _updateComposerState(pendingAttachments: const [], isUploading: false);
    if (mounted) {
      setState(() {});
    }

    _loadMessages();
    unawaited(_loadSecurityStatus());
    _startListening();
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

  Future<bool?> _showAttachmentOverflowDialog({required int totalBudgetBytes}) {
    final formattedTotal = formatPendingComposerBudgetBytes(totalBudgetBytes);
    final formattedLimit = formatPendingComposerBudgetBytes(
      widget.maxAttachmentBudgetBytes,
    );
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Media Too Large'),
        content: Text(
          'The attached media is $formattedTotal and exceeds the '
          '$formattedLimit limit. Would you like to compress and send, '
          'or cancel?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Compress'),
          ),
        ],
      ),
    );
  }

  void _showAttachmentTooLargeMessage() {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      const SnackBar(
        content: Text('The media is too large even after compression.'),
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
    if (_mimeFromPath(path) == 'image/gif') {
      final fileSize = File(path).lengthSync();
      if (fileSize > kMaxGifFileSize) {
        _showGifTooLargeMessage();
        throw const _RejectedPendingGroupMediaException();
      }
    }

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

  void _showGifTooLargeMessage() {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      const SnackBar(
        content: Text('GIF files larger than 25 MB cannot be added.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
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
          final safety = GroupMemberIdentitySafety.compare(
            member: member,
            savedContact: contact,
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
      });
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
        _messages = messages;
        _mediaMap = mediaMap;
        _initialLoadDone = true;
        _messageLoadErrorText = null;
        _historyGapRepair = historyGapRepair;
      });
      appliedMessages = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _emitNotificationTapTimingIfNeeded();
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

        MediaAttachment? downloaded;
        try {
          downloaded = await downloadMedia(
            bridge: widget.bridge,
            mediaAttachmentRepo: widget.mediaAttachmentRepo!,
            mediaFileManager: widget.mediaFileManager!,
            attachment: attachment,
            contactPeerId: widget.group.id,
            enforceGroupMediaPolicy: true,
          );
        } catch (_) {
          downloaded = null;
        }
        if (mounted) {
          setState(() {
            final list = List<MediaAttachment>.from(
              _mediaMap[entry.key] ?? entry.value,
            );
            final idx = list.indexWhere((a) => a.id == attachment.id);
            if (idx >= 0) {
              list[idx] =
                  downloaded ??
                  attachment.copyWith(
                    downloadStatus: kMediaDownloadStatusFailed,
                  );
              _updateMediaForMessage(entry.key, list);
            }
          });
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
                  message.id.startsWith('sys-group_dissolved:')) {
                unawaited(_refreshVisibleGroup());
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
        });
  }

  Future<void> _handleCurrentGroupRemoved() async {
    if (!mounted) return;

    widget.groupConversationTracker?.clearIfActive(_activeGroupConversationKey);
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      const SnackBar(
        content: Text('You were removed from this group.'),
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

    final hasAttachments = _pendingAttachments.isNotEmpty;
    if (text.isEmpty && !hasAttachments) return;
    if (!_tryBeginSendFlow()) return;
    final draftText = text;
    final quotedMessageId = _activeQuoteMessageId;
    final composerSnapshot = _GroupComposerSnapshot(
      draftText: draftText,
      quotedMessageId: quotedMessageId,
      pendingAttachments: List<PendingComposerMedia>.from(_pendingAttachments),
    );

    // 1. Generate IDs upfront for optimistic display
    final messageId = _uuid.v4();
    final now = DateTime.now().toUtc();

    // 2. Capture and clear pending attachments
    final mediaToUpload = List<PendingComposerMedia>.from(_pendingAttachments);
    if (!_validatePendingGroupMediaDescriptors(mediaToUpload)) {
      _endSendFlow();
      return;
    }
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
      status: 'sending',
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
    }

    // 4. sendGroupMessage() still owns the final message row save.
    final bgTaskId = await _beginBackgroundTaskGuarded();
    var prePersistedOrdinaryMediaRow = false;
    try {
      // 5. Upload attachments (if any)
      List<MediaAttachment>? uploadedAttachments;
      if (mediaToUpload.isNotEmpty) {
        _beginActiveAttachmentUpload(
          messageId: messageId,
          composerSnapshot: composerSnapshot,
        );
        final members = await widget.groupRepo.getMembers(widget.group.id);
        final allowedPeers = groupMediaAllowedPeersForMembers(members);

        try {
          if (_supportsDurableGroupMediaUploads) {
            final preparedUploads = await _prepareDurableGroupMediaUploads(
              messageId: messageId,
              mediaToUpload: mediaToUpload,
            );
            await widget.msgRepo.saveMessage(optimisticMessage);
            prePersistedOrdinaryMediaRow = true;
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
        if (mounted) {
          _removeLocalMessage(messageId);
        }
        try {
          await widget.mediaAttachmentRepo?.deleteAttachmentsForMessage(
            messageId,
          );
        } catch (_) {}
        try {
          await widget.mediaFileManager?.deletePendingUploadDir(messageId);
        } catch (_) {}
        try {
          if (prePersistedOrdinaryMediaRow) {
            await widget.msgRepo.deleteMessage(messageId);
          }
        } catch (_) {}
        if (result == SendGroupMessageResult.groupDissolved) {
          await _refreshVisibleGroup();
          if (mounted) {
            _showFloatingSnackBar('This group has been dissolved');
          }
        } else if (mounted && result == SendGroupMessageResult.unauthorized) {
          _showFloatingSnackBar(
            'You no longer have permission to send messages in this group.',
          );
        } else if (mounted && result == SendGroupMessageResult.groupNotFound) {
          _showFloatingSnackBar('This group is no longer available.');
        }
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
  }

  Future<void> _onRetryUnavailableMedia(
    String messageId,
    String attachmentId,
  ) async {
    final mediaAttachmentRepo = widget.mediaAttachmentRepo;
    final mediaFileManager = widget.mediaFileManager;
    if (mediaAttachmentRepo == null || mediaFileManager == null) {
      _showFloatingSnackBar(
        'Retry unavailable right now.',
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
        'Media unavailable right now.',
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

    final refreshedTarget = resolved
        .where((attachment) => attachment.id == attachmentId)
        .firstOrNull;
    if (refreshedTarget == null ||
        !GroupMediaIntegrityPolicy.canDisplayVerifiedGroupMedia(
          refreshedTarget,
        )) {
      _showFloatingSnackBar(
        'Media is still unavailable.',
        backgroundColor: Colors.red[700],
      );
    }
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
        'Retry unavailable right now.',
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
    final retried = await retryFailedGroupMessage(
      messageId: messageId,
      groupMsgRepo: widget.msgRepo,
      groupRepo: widget.groupRepo,
      identityRepo: widget.identityRepo,
      bridge: widget.bridge,
      mediaAttachmentRepo: mediaAttachmentRepo,
    );

    await _refreshMessageWithHydratedMedia(
      messageId,
      fallbackMedia: fallbackMedia,
    );

    if (retried == 0) {
      _showFloatingSnackBar(
        'Could not retry media message.',
        backgroundColor: Colors.red[700],
      );
    }
  }

  Future<void> _onDeleteFailedMedia(String messageId) async {
    final mediaAttachmentRepo = widget.mediaAttachmentRepo;
    final mediaFileManager = widget.mediaFileManager;
    if (mediaAttachmentRepo == null || mediaFileManager == null) {
      _showFloatingSnackBar(
        'Delete unavailable right now.',
        backgroundColor: Colors.red[700],
      );
      return;
    }

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

  Future<void> _restoreComposerSnapshot(
    _GroupComposerSnapshot snapshot,
    String messageId, {
    String? snackText,
    bool showSnackBar = false,
  }) async {
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
          resolved.add(await _markDisplayIntegrityFailed(attachment));
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

  bool _shouldRecoverVisibleAttachment(MediaAttachment attachment) {
    return attachment.downloadStatus == kMediaDownloadStatusPending ||
        attachment.downloadStatus == kMediaDownloadStatusDownloading ||
        attachment.downloadStatus == kMediaDownloadStatusFailed;
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
    final media = await _loadResolvedAttachmentsForMessage(latestMessage.id);
    if (!mounted) return;

    final preserveScrollOffset = _shouldPreserveScrollOffset();
    final previousOffset = _scrollController.hasClients
        ? _scrollController.position.pixels
        : 0.0;

    setState(() {
      _upsertMessage(latestMessage);
      _updateMediaForMessage(latestMessage.id, media);
    });

    _restoreScrollAfterMessageUpdate(
      preserveScrollOffset: preserveScrollOffset,
      previousOffset: previousOffset,
    );

    if (markAsRead) {
      await _markVisibleReadIfAllowed();
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
                  'Media Library',
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
                  'Take Photo',
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
                  'Record Video',
                  style: TextStyle(color: sheetColors.textPrimary),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickVideoFromCamera();
                },
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
    _updateComposerState(pendingAttachments: _pendingAttachmentFiles());
  }

  void _upsertMessage(GroupMessage message) {
    final updated = List<GroupMessage>.from(_messages);
    final index = updated.indexWhere((existing) => existing.id == message.id);
    if (index >= 0) {
      updated[index] = message;
    } else {
      updated.add(message);
    }
    _messages = orderGroupMessagesForTimeline(updated);
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
    final next = current.copyWith(
      pendingAttachments: pendingAttachments,
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

    final hasPermission = await recorder.requestPermission();
    if (!mounted || _pendingRecorderAbort) {
      _updateComposerState(
        recordingState: VoiceRecordingState.idle,
        recordingDuration: Duration.zero,
        amplitudeValues: const [],
      );
      return;
    }

    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Microphone permission is required to record voice messages.',
            ),
            backgroundColor: Colors.red[700],
            behavior: SnackBarBehavior.floating,
          ),
        );
        _updateComposerState(
          recordingState: VoiceRecordingState.idle,
          recordingDuration: Duration.zero,
          amplitudeValues: const [],
        );
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

      final messageId = _uuid.v4();
      final attachmentId = _uuid.v4();
      final now = DateTime.now().toUtc();
      final optimisticMessage = GroupMessage(
        id: messageId,
        groupId: widget.group.id,
        senderPeerId: _ownPeerId!,
        senderUsername: _senderUsername,
        text: '',
        timestamp: now,
        quotedMessageId: quotedMessageId,
        status: 'sending',
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
        if (mounted) {
          _updateComposerState(isUploading: false);
        }
        _updateLocalMessageStatus(messageId, 'failed');
        await _persistMessageStatus(messageId, 'failed');
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
          _restoreActiveQuoteIfNeeded(quotedMessageId);
          return;
        }

        final stableVoiceAttachment = await _buildStableVoiceAttachment(
          pendingAttachment: durablePendingAttachment,
          uploaded: voiceAttachment,
          absoluteDurablePath: durableAbsolutePath,
          waveform: waveform,
        );
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
          } else if (result == SendGroupMessageResult.groupNotFound ||
              result == SendGroupMessageResult.groupDissolved ||
              result == SendGroupMessageResult.unauthorized) {
            if (mounted) {
              _removeLocalMessage(messageId);
            }
            try {
              await mediaAttachmentRepo.deleteAttachmentsForMessage(messageId);
            } catch (_) {}
            try {
              await mediaFileManager.deletePendingUploadDir(messageId);
            } catch (_) {}
            await widget.msgRepo.deleteMessage(messageId);
            _restoreActiveQuoteIfNeeded(quotedMessageId);
            if (result == SendGroupMessageResult.groupDissolved) {
              await _refreshVisibleGroup();
              if (mounted) {
                _showFloatingSnackBar('This group has been dissolved');
              }
            } else if (mounted &&
                result == SendGroupMessageResult.unauthorized) {
              _showFloatingSnackBar(
                'You no longer have permission to send messages in this group.',
              );
            } else if (mounted &&
                result == SendGroupMessageResult.groupNotFound) {
              _showFloatingSnackBar('This group is no longer available.');
            }
          } else {
            _updateLocalMessageStatus(messageId, 'failed');
            await _persistMessageStatus(messageId, 'failed');
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
    setState(() {
      _activeQuoteMessageId = messageId;
    });
  }

  void _onClearQuote() {
    if (_activeQuoteMessageId == null) return;
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
              uploadMediaFn: widget.uploadMediaFn,
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
    if (_group.isDissolved) {
      return 'This group has been dissolved. History stays available, but new messages are disabled.';
    }
    if (!_isCurrentUserActiveMember) {
      return "You can read this group's history, but you are not an active member.";
    }
    if (!_hasCurrentSendKey) {
      return 'Waiting for the current group key before you can send.';
    }
    if (!_hasCompleteSenderIdentity) {
      return 'Waiting for your identity before you can send.';
    }
    return 'Only admins can send messages in this group';
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

  bool get _canWrite => _canWriteForGroup(_group);

  bool get _canMutateReactions =>
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

    setState(() {
      _group = refreshedGroup;
      _historyGapRepair = historyGapRepair;
    });
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
      _showFloatingSnackBar('This media type is not supported in groups.');
      return false;
    }
    final sizeValidation = GroupMediaSizePolicy.validateAttachments(
      media
          .map(
            (pending) => MediaAttachment(
              id: pending.file.path,
              messageId: '',
              mime: _mimeFromPath(pending.file.path),
              size: pending.budgetBytes,
              mediaType: MediaAttachment.mediaTypeFromMime(
                _mimeFromPath(pending.file.path),
              ),
              downloadStatus: 'upload_pending',
              createdAt: DateTime.now().toUtc().toIso8601String(),
            ),
          )
          .toList(growable: false),
    );
    if (!sizeValidation.isValid) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_CONV_FL_MEDIA_REJECTED_INVALID_SIZE',
        details: {'reason': sizeValidation.reason},
      );
      _showAttachmentTooLargeMessage();
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
      if (result == RemoveGroupReactionResult.success) {
        return;
      }
      if (result == RemoveGroupReactionResult.groupDissolved) {
        await _restoreReactionStateAfterDissolve(messageId, previousReactions);
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
    if (result == SendGroupReactionResult.success &&
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
    _showFloatingSnackBar('This group has been dissolved');
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
    _removedSubscription?.cancel();
    _reactionSubscription?.cancel();
    _mediaUploadProgressSubscription?.cancel();
    _durationSub?.cancel();
    _amplitudeSub?.cancel();
    if (_isRecording) {
      widget.audioRecorderService?.cancel();
    }
    _scrollController.dispose();
    _composerState.dispose();
    super.dispose();
  }

  String get _activeGroupConversationKey => 'group:${widget.group.id}';

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
            activeQuoteText: activeQuoteText,
            isActiveQuoteUnavailable: isActiveQuoteUnavailable,
            onClearQuote: _canWrite ? _onClearQuote : null,
            backlogRetentionNotice: groupBacklogRetentionNoticeFor(_group),
            historyGapRepairNotice: groupHistoryGapRepairNoticeFor(
              _historyGapRepair,
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
