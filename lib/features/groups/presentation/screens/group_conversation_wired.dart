import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/device/upload_wake_lock.dart';
import 'package:flutter_app/core/media/amplitude_buffer.dart';
import 'package:flutter_app/core/media/audio_recorder_service.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/media/downsample_waveform.dart';
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
import 'package:flutter_app/features/conversation/application/load_reactions_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_change.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/groups/application/remove_group_reaction_use_case.dart';
import 'package:flutter_app/features/groups/application/retry_failed_group_messages_use_case.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/application/send_group_reaction_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_reaction_replay_outbox_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/groups/presentation/group_backlog_retention_notice.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_screen.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_info_wired.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_reaction_details_sheet.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
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
  final UploadMediaFn uploadMediaFn;
  final int maxAttachmentBudgetBytes;
  final DateTime? notificationTappedAt;

  const GroupConversationWired({
    super.key,
    required this.group,
    required this.groupRepo,
    required this.msgRepo,
    required this.groupMessageListener,
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
    this.uploadMediaFn = uploadMedia,
    this.maxAttachmentBudgetBytes = kGeneralMediaAttachmentBudgetBytes,
    this.notificationTappedAt,
  });

  @override
  State<GroupConversationWired> createState() => _GroupConversationWiredState();
}

class _GroupConversationWiredState extends State<GroupConversationWired>
    with WidgetsBindingObserver {
  static const _maxAttachments = 10;
  static const _liveEdgeTolerance = 32.0;
  static final MediaPicker _defaultMediaPicker = SystemMediaPicker();

  late GroupModel _group;
  List<GroupMessage> _messages = [];
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

  bool get _isRecording => _composerViewState.recordingState.isActive;

  UploadProgressViewState? get _uploadProgressViewState {
    if (!_isTrackingRelayUpload || _trackedUploadTotalBytes <= 0) return null;
    return UploadProgressViewState(
      sentBytes: (_trackedUploadCompletedBytes + _trackedCurrentUploadBytes)
          .clamp(0, _trackedUploadTotalBytes),
      totalBytes: _trackedUploadTotalBytes,
    );
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _group = widget.group;
    _draftText = widget.initialText ?? '';
    widget.groupConversationTracker?.setActive('group:${widget.group.id}');
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
    final nextBytes = sentBytes.toInt().clamp(0, _trackedUploadTotalBytes);
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
    final nextCompleted = (_trackedUploadCompletedBytes + sizeBytes).clamp(
      0,
      _trackedUploadTotalBytes,
    );
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
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshVisibleGroup());
    }
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

  Future<void> _loadMessages() async {
    try {
      final messages = await widget.msgRepo.getMessagesPage(widget.group.id);
      if (!mounted) return;

      final mediaMap = await _loadResolvedMediaMap(messages);
      if (!mounted) return;

      setState(() {
        _messages = messages;
        _mediaMap = mediaMap;
        _initialLoadDone = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _emitNotificationTapTimingIfNeeded();
      });

      unawaited(_loadReactions(messages));
      unawaited(_downloadPendingMedia(mediaMap));
      await widget.msgRepo.markAsRead(widget.group.id);
    } catch (e) {
      if (mounted) {
        setState(() => _initialLoadDone = true);
      }
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_CONV_FL_LOAD_MESSAGES_ERROR',
        details: {'error': e.toString()},
      );
    }
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
                  downloaded ?? attachment.copyWith(downloadStatus: 'failed');
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

    widget.groupConversationTracker?.clear();
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
      final pendingAttachment = MediaAttachment(
        id: blobId,
        messageId: messageId,
        mime: mime,
        // Size is not required for the durable pre-upload contract.
        size: 0,
        mediaType: MediaAttachment.mediaTypeFromMime(mime),
        width: pending.width,
        height: pending.height,
        durationMs: pending.durationMs,
        localPath: durableRelativePath,
        downloadStatus: 'upload_pending',
        createdAt: createdAt,
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
      );
    }

    final absoluteOwnedPath = await mediaFileManager.localPathForAttachment(
      contactPeerId: widget.group.id,
      blobId: plan.pendingAttachment.id,
      mime: plan.pendingAttachment.mime,
    );
    final sourceFile = File(plan.absoluteDurablePath);
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
    );
  }

  Future<void> _onSend(String text) async {
    if (!_canWrite) return;
    if (_ownPeerId == null) return;

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
    final bgTaskId = await callBgBegin(widget.bridge);
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
        final allowedPeers = members.map((m) => m.peerId).toList();

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
            optimisticMedia = mediaToUpload
                .map((m) {
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
                    createdAt: now.toIso8601String(),
                  );
                })
                .toList(growable: false);
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
                uploadedAttachments.add(
                  result.copyWith(
                    id: attachmentId,
                    messageId: messageId,
                    downloadStatus: 'done',
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
      await callBgEnd(widget.bridge, bgTaskId);
      _endSendFlow();
    }
  }

  void _onDraftChanged(String text) {
    if (_draftText == text) return;
    setState(() => _draftText = text);
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

  Future<void> _restoreComposerSnapshot(
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
      });
      _updateComposerState(
        pendingAttachments: _pendingAttachmentFiles(),
        isUploading: false,
      );
      _updateLocalMessageStatus(messageId, 'failed');
    }
    await _persistMessageStatus(messageId, 'failed');
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

    return _resolveAttachmentsForDisplay(attachments);
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
    final mediaMap = <String, List<MediaAttachment>>{};
    for (final entry in rawMap.entries) {
      mediaMap[entry.key] = await _resolveAttachmentsForDisplay(entry.value);
    }
    return mediaMap;
  }

  Future<List<MediaAttachment>> _loadResolvedAttachmentsForMessage(
    String messageId,
  ) async {
    final mediaRepo = widget.mediaAttachmentRepo;
    if (mediaRepo == null) return const [];
    final attachments = await mediaRepo.getAttachmentsForMessage(messageId);
    return _resolveAttachmentsForDisplay(attachments);
  }

  Future<List<MediaAttachment>> _resolveAttachmentsForDisplay(
    List<MediaAttachment> attachments,
  ) async {
    final mediaFileManager = widget.mediaFileManager;
    if (mediaFileManager == null) {
      return attachments;
    }

    final resolved = <MediaAttachment>[];
    for (final attachment in attachments) {
      if (attachment.localPath == null) {
        resolved.add(attachment);
        continue;
      }
      final absolutePath = await mediaFileManager.resolveStoredPath(
        attachment.localPath!,
      );
      if (_isPendingUploadPath(attachment.localPath!) ||
          _isPendingUploadPath(absolutePath)) {
        resolved.add(attachment.copyWith(localPath: absolutePath));
        continue;
      }
      final exists = await File(absolutePath).exists();
      if (!exists && attachment.downloadStatus == 'done') {
        resolved.add(
          attachment.copyWith(
            localPath: absolutePath,
            downloadStatus: 'pending',
          ),
        );
        continue;
      }
      resolved.add(attachment.copyWith(localPath: absolutePath));
    }
    return resolved;
  }

  bool _shouldRecoverVisibleAttachment(MediaAttachment attachment) {
    return attachment.downloadStatus == 'pending' ||
        attachment.downloadStatus == 'downloading' ||
        attachment.downloadStatus == 'failed';
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
      await widget.msgRepo.markAsRead(widget.group.id);
    }
  }

  // -------------------------------------------------------------------------
  // Attachment picker
  // -------------------------------------------------------------------------

  void _onAttach() {
    if (!_canWrite) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[600],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.white),
              title: const Text(
                'Media Library',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _pickFromGallery();
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.white),
              title: const Text(
                'Take Photo',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _pickFromCamera();
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam, color: Colors.white),
              title: const Text(
                'Record Video',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _pickVideoFromCamera();
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
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
    updated.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    _messages = updated;
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
      final targetOffset = previousOffset.clamp(0.0, maxExtent);
      _scrollController.jumpTo(targetOffset);
    });
  }

  // -------------------------------------------------------------------------
  // Voice recording
  // -------------------------------------------------------------------------

  Future<void> _onRecordStart() async {
    if (!_canWrite) return;
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
        durableRelativePath = await mediaFileManager.copyToDurableStorage(
          sourceFilePath: recording.filePath,
          messageId: messageId,
          attachmentId: attachmentId,
          mime: recording.mime,
        );
        absoluteDurablePath = await mediaFileManager.resolveStoredPath(
          durableRelativePath,
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

      final bgTaskId = await callBgBegin(widget.bridge);
      try {
        final members = await widget.groupRepo.getMembers(widget.group.id);
        final allowedPeers = members.map((m) => m.peerId).toList();

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

        final stableVoiceAttachment = voiceAttachment.copyWith(
          id: attachmentId,
          messageId: messageId,
          downloadStatus: 'done',
          uploadRetryCount: durablePendingAttachment.uploadRetryCount,
        );
        _markRelayUploadCompleted(recording.sizeBytes);
        await _stopRelayUploadTracking();

        if (mounted) {
          _updateComposerState(isUploading: false);
        }

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
            }
          } else {
            _updateLocalMessageStatus(messageId, 'failed');
            await _persistMessageStatus(messageId, 'failed');
            _restoreActiveQuoteIfNeeded(quotedMessageId);
          }
        } catch (_) {}
      } finally {
        await _stopRelayUploadTracking();
        await callBgEnd(widget.bridge, bgTaskId);
      }
    } finally {
      _endSendFlow();
    }
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
    if (index < visual.length && visual[index].localPath != null) {
      final allPaths = visual
          .where((a) => a.localPath != null && a.downloadStatus == 'done')
          .map((a) => a.localPath!)
          .toList();
      if (allPaths.isEmpty) return;
      final tappedPath = visual[index].localPath!;
      final startIndex = allPaths
          .indexOf(tappedPath)
          .clamp(0, allPaths.length - 1);

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
              contactRepo: widget.contactRepo,
              bridge: widget.bridge,
              identityRepo: widget.identityRepo,
              p2pService: widget.p2pService,
              imageProcessor: widget.imageProcessor,
              mediaPicker: widget.mediaPicker,
              uploadMediaFn: widget.uploadMediaFn,
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
    if (group.type == GroupType.announcement &&
        group.myRole != GroupRole.admin) {
      return false;
    }
    return true;
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
      !_group.isDissolved &&
      widget.reactionRepo != null &&
      widget.groupReactionReplayOutboxRepository != null;

  Future<void> _refreshVisibleGroup() async {
    final refreshedGroup = await widget.groupRepo.getGroup(widget.group.id);
    if (refreshedGroup == null || !mounted) {
      return;
    }

    setState(() => _group = refreshedGroup);
  }

  Future<void> _refreshAfterInfoRoute() async {
    await _refreshVisibleGroup();
    await _loadMessages();
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

      final result = await removeGroupReaction(
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
      if (result == RemoveGroupReactionResult.groupDissolved) {
        await _restoreReactionStateAfterDissolve(messageId, previousReactions);
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

    final (result, reaction) = await sendGroupReaction(
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

    if (result == SendGroupReactionResult.success && reaction != null) {
      if (!mounted) return;
      setState(() {
        final list = List<MessageReaction>.from(_reactions[messageId] ?? []);
        list.removeWhere((r) => r.id == '' && r.senderPeerId == _ownPeerId);
        list.add(reaction);
        _reactions = {..._reactions, messageId: list};
      });
    } else if (result == SendGroupReactionResult.groupDissolved) {
      await _restoreReactionStateAfterDissolve(messageId, previousReactions);
    }
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
      backgroundColor: const Color(0xFF141A24),
      showDragHandle: false,
      builder: (_) =>
          GroupReactionDetailsSheet(emoji: emoji, participants: participants),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.groupConversationTracker?.clear();
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

    return PopScope(
      canPop: !_isTrackingRelayUpload || _allowPopDuringActiveUpload,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || !_isTrackingRelayUpload) return;
        unawaited(_onBack());
      },
      child: GroupConversationScreen(
        group: _group,
        messages: _messages,
        ownPeerId: _ownPeerId,
        onSend: _onSend,
        onBack: _onBack,
        onInfo: _onInfo,
        canWrite: _canWrite,
        isSending: _isSending,
        uploadProgress: _uploadProgressViewState,
        onCancelUpload:
            _activeAttachmentUpload == null ||
                _activeAttachmentUpload!.cancelRequested
            ? null
            : _requestCancelActiveAttachmentUpload,
        initialLoadDone: _initialLoadDone,
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
        onReactionSelected: _canMutateReactions ? _onReactionSelected : null,
        initialText: _draftText,
        onDraftChanged: _onDraftChanged,
        onQuoteReply: _canWrite ? _onQuoteReply : null,
        onRetryFailedMedia:
            _canWrite &&
                widget.mediaAttachmentRepo != null &&
                widget.mediaFileManager != null
            ? _onRetryFailedMedia
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
      ),
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
