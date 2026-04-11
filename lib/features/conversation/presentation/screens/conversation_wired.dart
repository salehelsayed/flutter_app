import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart' as intl;
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/device/upload_wake_lock.dart';
import 'package:flutter_app/core/constants/media_constants.dart';
import 'package:flutter_app/core/media/amplitude_buffer.dart';
import 'package:flutter_app/core/media/audio_recorder_service.dart';
import 'package:flutter_app/core/media/downsample_waveform.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_picker.dart';
import 'package:flutter_app/core/media/pending_composer_media.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/features/settings/domain/models/image_quality_preference.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/utils/text_sanitizer.dart';
import 'package:flutter_app/features/contacts/application/block_contact_use_case.dart';
import 'package:flutter_app/features/contacts/application/delete_contact_use_case.dart';
import 'package:flutter_app/features/contacts/application/unblock_contact_use_case.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/delete_message_use_case.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/confirmation_dialog.dart';
import 'package:flutter_app/features/conversation/application/download_media_use_case.dart';
import 'package:flutter_app/features/conversation/application/load_conversation_use_case.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/conversation/application/mark_conversation_read_use_case.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/send_voice_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/audio_recording.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/conversation/application/load_reactions_use_case.dart';
import 'package:flutter_app/features/conversation/application/reaction_listener.dart';
import 'package:flutter_app/features/conversation/application/retry_failed_messages_use_case.dart';
import 'package:flutter_app/features/conversation/application/send_reaction_use_case.dart';
import 'package:flutter_app/features/conversation/application/remove_reaction_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_change.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/compose_area.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/upload_progress_banner.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/introduction/application/check_intro_banner_use_case.dart';
import 'package:flutter_app/features/introduction/application/introduction_copy.dart';
import 'package:flutter_app/features/introduction/application/insert_intro_system_message.dart';
import 'package:flutter_app/features/introduction/domain/repositories/introduction_repository.dart';
import 'package:flutter_app/features/introduction/presentation/screens/friend_picker_wired.dart';
import 'package:flutter_app/features/introduction/presentation/screens/sent_confirmation_wired.dart';
import 'package:flutter_app/shared/widgets/media/media_preview_text.dart';
import 'conversation_screen.dart';

typedef SendChatMessageFn =
    Future<(SendChatMessageResult, ConversationMessage?)> Function({
      required P2PService p2pService,
      required MessageRepository messageRepo,
      required String targetPeerId,
      required String text,
      required String senderPeerId,
      required String senderUsername,
      String? messageId,
      String? timestamp,
      Bridge? bridge,
      String? recipientMlKemPublicKey,
      String? quotedMessageId,
      List<MediaAttachment>? mediaAttachments,
      MediaAttachmentRepository? mediaAttachmentRepo,
    });

typedef SendVoiceMessageFn =
    Future<(SendVoiceMessageResult, ConversationMessage?)> Function({
      required P2PService p2pService,
      required MessageRepository messageRepo,
      required String targetPeerId,
      required String senderPeerId,
      required String senderUsername,
      required AudioRecording recording,
      required Bridge bridge,
      String? recipientMlKemPublicKey,
      MediaAttachmentRepository? mediaAttachmentRepo,
      MediaFileManager? mediaFileManager,
      String? text,
      String? quotedMessageId,
      List<double>? waveform,
      String? messageId,
      String? timestamp,
      String? blobId,
    });

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

class _PreparedConversationMediaUpload {
  final PendingComposerMedia source;
  final MediaAttachment pendingAttachment;
  final String absoluteDurablePath;

  const _PreparedConversationMediaUpload({
    required this.source,
    required this.pendingAttachment,
    required this.absoluteDurablePath,
  });
}

class _RejectedPendingMediaException implements Exception {
  const _RejectedPendingMediaException();
}

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

typedef DeleteContactFn = Future<void> Function(String peerId);

/// Wired widget that connects ConversationScreen to business logic.
///
/// Loads identity and messages on init, subscribes to incoming message stream,
/// and handles sending messages via use cases.
class ConversationWired extends StatefulWidget {
  static const deleteSheetKey = ValueKey('conversation-delete-message-sheet');
  static const deletePromptKey = ValueKey('conversation-delete-message-prompt');
  static const deleteForMeKey = ValueKey('conversation-delete-for-me-action');
  static const deleteForEveryoneKey = ValueKey(
    'conversation-delete-for-everyone-action',
  );
  static const deleteCancelKey = ValueKey('conversation-delete-cancel-action');

  final ContactModel contact;
  final IdentityRepository identityRepo;
  final MessageRepository messageRepo;
  final ChatMessageListener chatMessageListener;
  final P2PService p2pService;
  final Bridge? bridge;
  final SendChatMessageFn sendChatMessageFn;
  final EditChatMessageFn editChatMessageFn;
  final DeleteMessageForMeFn deleteMessageForMeFn;
  final DeleteMessageForEveryoneFn deleteMessageForEveryoneFn;
  final List<ConversationMessage>? initialMessages;
  final ContactRepository? contactRepo;
  final MediaAttachmentRepository? mediaAttachmentRepo;
  final MediaFileManager? mediaFileManager;
  final List<File>? initialAttachments;
  final List<PendingComposerMedia>? initialPendingMedia;
  final String? initialText;
  final ImageProcessor? imageProcessor;
  final MediaPicker? mediaPicker;
  final ImageQualityPreference qualityPreference;
  final ImageQualityPreference videoQualityPreference;
  final int maxAttachmentBudgetBytes;
  final ActiveConversationTracker? conversationTracker;
  final AudioRecorderService? audioRecorderService;
  final ReactionRepository? reactionRepo;
  final ReactionListener? reactionListener;
  final IntroductionRepository? introductionRepository;
  final DeleteContactFn? deleteContactFn;
  final UploadMediaFn uploadMediaFn;
  final SendVoiceMessageFn sendVoiceMessageFn;

  const ConversationWired({
    super.key,
    required this.contact,
    required this.identityRepo,
    required this.messageRepo,
    required this.chatMessageListener,
    required this.p2pService,
    this.bridge,
    this.sendChatMessageFn = sendChatMessage,
    this.editChatMessageFn = editChatMessage,
    this.deleteMessageForMeFn = deleteMessageForMe,
    this.deleteMessageForEveryoneFn = deleteMessageForEveryone,
    this.initialMessages,
    this.contactRepo,
    this.mediaAttachmentRepo,
    this.mediaFileManager,
    this.initialAttachments,
    this.initialPendingMedia,
    this.initialText,
    this.imageProcessor,
    this.mediaPicker,
    this.qualityPreference = ImageQualityPreference.compressed,
    this.videoQualityPreference = ImageQualityPreference.compressed,
    this.maxAttachmentBudgetBytes = kGeneralMediaAttachmentBudgetBytes,
    this.conversationTracker,
    this.audioRecorderService,
    this.reactionRepo,
    this.reactionListener,
    this.introductionRepository,
    this.deleteContactFn,
    this.uploadMediaFn = uploadMedia,
    this.sendVoiceMessageFn = sendVoiceMessage,
  });

  @override
  State<ConversationWired> createState() => _ConversationWiredState();
}

class _ConversationWiredState extends State<ConversationWired> {
  static const _uuid = Uuid();
  static const _pageSize = 50;
  static final MediaPicker _defaultMediaPicker = SystemMediaPicker();

  IdentityModel? _identity;
  late ContactModel _contact;
  List<ConversationMessage> _messages = [];
  StreamSubscription<ConversationMessage>? _incomingSubscription;
  StreamSubscription<ConversationMessage>? _repoChangeSubscription;
  StreamSubscription<ContactModel>? _contactUpdateSubscription;
  final _scrollController = ScrollController();

  bool _hasMoreOlderMessages = true;
  bool _isLoadingMore = false;
  bool _initialLoadDone = false;
  bool _isSending = false;

  List<PendingComposerMedia> _pendingAttachments = [];
  final _composerState = ValueNotifier(const ConversationComposerViewState());
  static const _maxAttachments = 10;

  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<double>? _amplitudeSub;
  final _amplitudeBuffer = AmplitudeBuffer(size: 25);
  List<double> _waveformSamples = [];
  bool _pendingRecorderAbort = false;

  // Reaction state
  Map<String, List<MessageReaction>> _reactions = {};
  StreamSubscription<ReactionChange>? _reactionSubscription;
  StreamSubscription<Map<String, dynamic>>? _mediaUploadProgressSubscription;

  // Introduction banner state
  bool _showIntroBanner = false;
  bool _hasOtherFriends = false;
  String? _activeQuoteMessageId;
  String? _editingMessageId;
  String? _editingOriginalText;
  String _draftText = '';
  bool _isTrackingRelayUpload = false;
  int _trackedUploadTotalBytes = 0;
  int _trackedUploadCompletedBytes = 0;
  int _trackedCurrentUploadBytes = 0;
  String? _trackedCurrentUploadId;
  bool _allowPopDuringActiveUpload = false;
  _ActiveAttachmentUpload? _activeAttachmentUpload;

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

  bool get _supportsDurableMediaUploads =>
      widget.mediaAttachmentRepo != null && widget.mediaFileManager != null;

  Future<List<_PreparedConversationMediaUpload>> _prepareDurableMediaUploads({
    required String messageId,
    required List<PendingComposerMedia> mediaToUpload,
    required List<MediaAttachment> optimisticMedia,
  }) async {
    final mediaAttachmentRepo = widget.mediaAttachmentRepo;
    final mediaFileManager = widget.mediaFileManager;
    if (mediaAttachmentRepo == null ||
        mediaFileManager == null ||
        mediaToUpload.isEmpty ||
        optimisticMedia.length != mediaToUpload.length) {
      return const [];
    }

    final preparedUploads = <_PreparedConversationMediaUpload>[];

    for (var index = 0; index < mediaToUpload.length; index++) {
      final pending = mediaToUpload[index];
      final optimisticAttachment = optimisticMedia[index];
      final durableRelativePath = await mediaFileManager.copyToDurableStorage(
        sourceFilePath: pending.file.path,
        messageId: messageId,
        attachmentId: optimisticAttachment.id,
        mime: optimisticAttachment.mime,
      );
      final absoluteDurablePath = await mediaFileManager.resolveStoredPath(
        durableRelativePath,
      );
      final durableAttachment = optimisticAttachment.copyWith(
        messageId: messageId,
        localPath: durableRelativePath,
        downloadStatus: 'upload_pending',
      );
      await mediaAttachmentRepo.saveAttachment(durableAttachment);
      preparedUploads.add(
        _PreparedConversationMediaUpload(
          source: pending,
          pendingAttachment: durableAttachment,
          absoluteDurablePath: absoluteDurablePath,
        ),
      );
    }

    await Future<void>.delayed(Duration.zero);
    return preparedUploads;
  }

  Future<MediaAttachment> _buildLocalSuccessAttachmentFromPlan({
    required String messageId,
    required _PreparedConversationMediaUpload plan,
  }) async {
    final mediaFileManager = widget.mediaFileManager;
    if (mediaFileManager == null) {
      return plan.pendingAttachment.copyWith(
        messageId: messageId,
        size: plan.source.budgetBytes,
        localPath: plan.absoluteDurablePath,
        downloadStatus: 'done',
      );
    }

    final absoluteOwnedPath = await mediaFileManager.localPathForAttachment(
      contactPeerId: _contact.peerId,
      blobId: plan.pendingAttachment.id,
      mime: plan.pendingAttachment.mime,
    );
    final sourceFile = File(plan.absoluteDurablePath);
    if (!await sourceFile.exists()) {
      return plan.pendingAttachment.copyWith(
        messageId: messageId,
        size: plan.source.budgetBytes,
        localPath: plan.absoluteDurablePath,
        downloadStatus: 'done',
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

    return plan.pendingAttachment.copyWith(
      messageId: messageId,
      size: plan.source.budgetBytes,
      localPath: mediaFileManager.relativePathForAttachment(
        contactPeerId: _contact.peerId,
        blobId: plan.pendingAttachment.id,
        mime: plan.pendingAttachment.mime,
      ),
      downloadStatus: 'done',
    );
  }

  Future<MediaAttachment> _finalizeUploadedAttachmentFromPlan({
    required String messageId,
    required _PreparedConversationMediaUpload plan,
    required MediaAttachment uploaded,
  }) async {
    final stableAttachment = await _buildLocalSuccessAttachmentFromPlan(
      messageId: messageId,
      plan: plan,
    );
    return uploaded.copyWith(
      id: plan.pendingAttachment.id,
      messageId: messageId,
      size: uploaded.size > 0 ? uploaded.size : stableAttachment.size,
      mediaType: plan.pendingAttachment.mediaType,
      width: uploaded.width ?? stableAttachment.width,
      height: uploaded.height ?? stableAttachment.height,
      durationMs: uploaded.durationMs ?? stableAttachment.durationMs,
      localPath: stableAttachment.localPath,
      downloadStatus: 'done',
      uploadRetryCount: plan.pendingAttachment.uploadRetryCount,
      waveform: uploaded.waveform,
    );
  }

  @override
  void initState() {
    super.initState();
    _contact = widget.contact;
    _draftText = widget.initialText ?? '';
    widget.conversationTracker?.setActive(widget.contact.peerId);
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
    emitFlowEvent(layer: 'FL', event: 'CONV_FL_SCREEN_INIT', details: {});
    _mediaUploadProgressSubscription = mediaUploadProgressStream.listen(
      _handleMediaUploadProgress,
    );
    _scrollController.addListener(_onScroll);
    _loadIdentity();
    if (widget.initialMessages != null) {
      _messages = widget.initialMessages!;
      _hasMoreOlderMessages = _messages.length >= _pageSize;
      _scrollToBottom();
      _markAsRead();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _initialLoadDone = true);
      });
    } else {
      _loadInitialPage().then((_) => _markAsRead());
    }
    _startListeningForMessages();
    _startListeningForOutgoingMessageChanges();
    _startListeningForContactUpdates();
    _startListeningForReactions();
    _checkIntroBanner();
    _checkHasOtherFriends();
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

  Future<void> _handleBackNavigation() async {
    final shouldPop = await _confirmLeaveWhileUploadActive();
    if (!shouldPop || !mounted) return;
    setState(() => _allowPopDuringActiveUpload = true);
    Navigator.of(context).pop();
  }

  void _beginActiveAttachmentUpload({
    required String messageId,
    required _ComposerSnapshot composerSnapshot,
  }) {
    final next = _ActiveAttachmentUpload(
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

  Future<bool> _cancelActiveAttachmentUploadIfRequested({
    required ScaffoldMessengerState? messenger,
  }) async {
    final activeUpload = _activeAttachmentUpload;
    if (activeUpload == null || !activeUpload.cancelRequested) {
      return false;
    }
    await _markUploadPendingAttachmentsCancelledForMessage(
      activeUpload.messageId,
    );
    await _stopRelayUploadTracking();
    _clearActiveAttachmentUpload();
    await _restoreComposerSnapshot(
      activeUpload.composerSnapshot,
      optimisticMessageId: activeUpload.messageId,
      messenger: messenger,
      snackText: 'Upload cancelled.',
    );
    return true;
  }

  Future<void> _markUploadPendingAttachmentsCancelledForMessage(
    String messageId,
  ) async {
    final mediaAttachmentRepo = widget.mediaAttachmentRepo;
    if (mediaAttachmentRepo == null) return;

    final attachments = await mediaAttachmentRepo.getAttachmentsForMessage(
      messageId,
    );
    for (final attachment in attachments) {
      if (attachment.downloadStatus != 'upload_pending') {
        continue;
      }
      await mediaAttachmentRepo.saveAttachment(
        attachment.copyWith(downloadStatus: 'upload_cancelled'),
      );
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
        throw const _RejectedPendingMediaException();
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

  Future<void> _checkIntroBanner() async {
    final contactRepo = widget.contactRepo;
    if (contactRepo == null) return;

    final show = await shouldShowIntroBanner(
      contactRepo: contactRepo,
      contact: _contact,
      messageCount: _messages.length,
    );
    if (mounted && show != _showIntroBanner) {
      setState(() => _showIntroBanner = show);
    }
  }

  Future<void> _checkHasOtherFriends() async {
    final contactRepo = widget.contactRepo;
    if (contactRepo == null) return;

    final activeContacts = await contactRepo.getActiveContacts();
    final others = activeContacts
        .where((c) => c.peerId != _contact.peerId && !c.isBlocked)
        .toList();
    if (mounted) {
      setState(() => _hasOtherFriends = others.isNotEmpty);
    }
  }

  Future<void> _onMaybeLater() async {
    final contactRepo = widget.contactRepo;
    if (contactRepo == null) return;

    await contactRepo.dismissIntroBanner(_contact.peerId);
    if (mounted) {
      setState(() => _showIntroBanner = false);
      _contact = _contact.copyWith(introsBannerDismissed: true);
    }
  }

  void _onMakeIntroductions() {
    // The FriendPickerWired integration is handled at a higher level.
    // For now, this triggers the same flow as the overflow menu introduce action.
    _onIntroduce();
  }

  void _onIntroduce() {
    final introRepo = widget.introductionRepository;
    final contactRepo = widget.contactRepo;
    emitFlowEvent(
      layer: 'FL',
      event: 'CONV_FL_INTRODUCE_TAP',
      details: {
        'introRepoNull': introRepo == null,
        'contactRepoNull': contactRepo == null,
        'bridgeNull': widget.bridge == null,
      },
    );
    if (introRepo == null || contactRepo == null) return;

    emitFlowEvent(
      layer: 'FL',
      event: 'CONV_FL_INTRODUCE_TRIGGERED',
      details: {'contactPeerId': _contact.peerId},
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => FriendPickerWired(
        recipient: _contact,
        contactRepo: contactRepo,
        introRepo: introRepo,
        p2pService: widget.p2pService,
        bridge: widget.bridge!,
        identityRepo: widget.identityRepo,
        onIntroductionsSent: (intros) {
          // Insert system message into conversation history
          final identity = _identity;
          if (identity != null && intros.isNotEmpty) {
            insertIntroSystemMessage(
              messageRepo: widget.messageRepo,
              contactPeerId: _contact.peerId,
              text: formatIntroducerIntroductionSystemMessage(
                recipientUsername: _contact.username,
                introducedUsernames: intros
                    .map((intro) => intro.introducedUsername ?? '')
                    .toList(growable: false),
              ),
              ownPeerId: identity.peerId,
            ).then((_) {
              if (mounted) _loadInitialPage();
            });
          }
          Navigator.of(sheetContext).pop();
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SentConfirmationWired(
                introductionCount: intros.length,
                introducedUsernames: intros
                    .map((i) => i.introducedUsername ?? 'Unknown')
                    .toList(),
                onBackToConversation: () => Navigator.of(context).pop(),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _loadIdentity() async {
    try {
      final identity = await widget.identityRepo.loadIdentity();
      if (identity != null && mounted) {
        setState(() => _identity = identity);
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONV_FL_IDENTITY_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _loadInitialPage() async {
    try {
      final messages = await loadConversationPage(
        messageRepo: widget.messageRepo,
        contactPeerId: _contact.peerId,
        pageSize: _pageSize,
        mediaAttachmentRepo: widget.mediaAttachmentRepo,
        mediaFileManager: widget.mediaFileManager,
      );
      if (mounted) {
        setState(() {
          _messages = messages;
          _hasMoreOlderMessages = messages.length >= _pageSize;
        });
        emitFlowEvent(
          layer: 'FL',
          event: 'CONV_FL_MESSAGES_LOADED',
          details: {'count': messages.length},
        );
        _scrollToBottom();
        await _loadReactions(messages);
        unawaited(_recoverVisibleMedia(messages));
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _initialLoadDone = true);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _initialLoadDone = true);
      }
      emitFlowEvent(
        layer: 'FL',
        event: 'CONV_FL_LOAD_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  void _onScroll() {
    if (!_hasMoreOlderMessages || _isLoadingMore) return;
    if (!_scrollController.hasClients) return;
    // In a reversed ListView, minScrollExtent is the "top" (oldest messages)
    final position = _scrollController.position;
    if (position.pixels <= position.minScrollExtent + 200) {
      _loadOlderMessages();
    }
  }

  Future<void> _loadOlderMessages() async {
    if (_messages.isEmpty) return;
    setState(() => _isLoadingMore = true);

    try {
      final cursor = _messages.first.timestamp;
      final olderMessages = await loadConversationPage(
        messageRepo: widget.messageRepo,
        contactPeerId: _contact.peerId,
        pageSize: _pageSize,
        beforeTimestamp: cursor,
        mediaAttachmentRepo: widget.mediaAttachmentRepo,
        mediaFileManager: widget.mediaFileManager,
      );
      if (mounted) {
        setState(() {
          _messages = [...olderMessages, ..._messages];
          _hasMoreOlderMessages = olderMessages.length >= _pageSize;
          _isLoadingMore = false;
        });
        unawaited(_recoverVisibleMedia(olderMessages));
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingMore = false);
      emitFlowEvent(
        layer: 'FL',
        event: 'CONV_FL_LOAD_MORE_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _recoverVisibleMedia(List<ConversationMessage> messages) async {
    final bridge = widget.bridge;
    final mediaAttachmentRepo = widget.mediaAttachmentRepo;
    final mediaFileManager = widget.mediaFileManager;
    if (bridge == null ||
        mediaAttachmentRepo == null ||
        mediaFileManager == null ||
        messages.isEmpty) {
      return;
    }

    for (final message in messages) {
      final storedAttachments = await mediaAttachmentRepo
          .getAttachmentsForMessage(message.id);
      if (storedAttachments.isEmpty) {
        continue;
      }

      final displayAttachments = <MediaAttachment>[];
      var didMutateDisplayState = false;
      for (final attachment in storedAttachments) {
        final resolved = await _resolveAttachmentForDisplay(attachment);
        if (_shouldRecoverVisibleAttachment(resolved)) {
          MediaAttachment? downloaded;
          try {
            downloaded = await downloadMedia(
              bridge: bridge,
              mediaAttachmentRepo: mediaAttachmentRepo,
              mediaFileManager: mediaFileManager,
              attachment: resolved,
              contactPeerId: message.contactPeerId,
            );
          } catch (_) {
            downloaded = null;
          }
          displayAttachments.add(
            downloaded ?? resolved.copyWith(downloadStatus: 'failed'),
          );
          didMutateDisplayState = true;
          continue;
        }

        displayAttachments.add(resolved);
        if (resolved.localPath != attachment.localPath ||
            resolved.downloadStatus != attachment.downloadStatus) {
          didMutateDisplayState = true;
        }
      }

      if (!didMutateDisplayState || !mounted) {
        continue;
      }

      final latestMessage = await widget.messageRepo.getMessage(message.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _upsertMessageById(
          (latestMessage ?? message).copyWith(media: displayAttachments),
        );
      });
    }
  }

  bool _shouldRecoverVisibleAttachment(MediaAttachment attachment) {
    return attachment.downloadStatus == 'pending' ||
        attachment.downloadStatus == 'downloading' ||
        attachment.downloadStatus == 'failed';
  }

  Future<MediaAttachment> _resolveAttachmentForDisplay(
    MediaAttachment attachment,
  ) async {
    final mediaFileManager = widget.mediaFileManager;
    if (mediaFileManager == null || attachment.localPath == null) {
      return attachment;
    }

    final absolutePath = await mediaFileManager.resolveStoredPath(
      attachment.localPath!,
    );
    if (_isPendingUploadPath(attachment.localPath!) ||
        _isPendingUploadPath(absolutePath)) {
      return attachment.copyWith(localPath: absolutePath);
    }
    final exists = await File(absolutePath).exists();
    if (!exists && attachment.downloadStatus == 'done') {
      return attachment.copyWith(
        localPath: absolutePath,
        downloadStatus: 'pending',
      );
    }

    return attachment.copyWith(localPath: absolutePath);
  }

  bool _isPendingUploadPath(String path) {
    return path.contains('pending_uploads/') ||
        path.contains('pending_uploads\\');
  }

  Future<void> _markAsRead() async {
    try {
      await markConversationRead(
        messageRepo: widget.messageRepo,
        contactPeerId: _contact.peerId,
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONV_FL_MARK_READ_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  void _startListeningForMessages() {
    _incomingSubscription = widget.chatMessageListener.incomingMessageStream
        .where((msg) => msg.contactPeerId == _contact.peerId)
        .listen(
          _onIncomingMessage,
          onError: (error) {
            emitFlowEvent(
              layer: 'FL',
              event: 'CONV_CHAT_STREAM_ERROR',
              details: {'error': error.toString()},
            );
          },
          onDone: () {
            emitFlowEvent(
              layer: 'FL',
              event: 'CONV_CHAT_STREAM_DONE',
              details: {},
            );
          },
        );
  }

  void _startListeningForOutgoingMessageChanges() {
    final messageRepo = widget.messageRepo;
    if (messageRepo is! MessageRepositoryChangeSource) {
      return;
    }

    final changeSource = messageRepo as MessageRepositoryChangeSource;
    _repoChangeSubscription = changeSource.messageChanges
        .where(
          (message) =>
              message.contactPeerId == _contact.peerId &&
              ((!message.isIncoming &&
                      _shouldRefreshFromRepositoryChange(message.status)) ||
                  message.isDeleted),
        )
        .listen(
          (message) async {
            if (!mounted) return;
            final hydratedMedia = message.isDeleted
                ? message.media
                : await _resolveHydratedMediaForMessage(
                    message.id,
                    fallbackMedia: message.media,
                  );
            if (!mounted) return;
            setState(() {
              _upsertMessageById(message.copyWith(media: hydratedMedia));
            });
          },
          onError: (error) {
            emitFlowEvent(
              layer: 'FL',
              event: 'CONV_REPO_CHANGE_STREAM_ERROR',
              details: {'error': error.toString()},
            );
          },
        );
  }

  bool _shouldRefreshFromRepositoryChange(String status) =>
      status == 'sent' || status == 'delivered' || status == 'failed';

  void _onIncomingMessage(ConversationMessage message) {
    if (!mounted) return;
    setState(() {
      _upsertMessageById(message);
    });
    _scrollToBottom();
    _markAsRead();
    // Auto-dismiss intro banner when message count reaches threshold
    if (_showIntroBanner && _messages.length >= 3) {
      _onMaybeLater();
    }
  }

  void _onQuoteReply(String messageId) {
    if (!mounted) return;
    setState(() {
      _editingMessageId = null;
      _editingOriginalText = null;
      _activeQuoteMessageId = messageId;
    });
  }

  void _onClearQuote() {
    if (!mounted) return;
    setState(() => _activeQuoteMessageId = null);
  }

  void _onEditMessage(String messageId) {
    if (!mounted || !_canEnterEditMode) return;
    final message = _messages.where((m) => m.id == messageId).firstOrNull;
    if (message == null || message.isIncoming || message.text.trim().isEmpty) {
      return;
    }

    setState(() {
      _activeQuoteMessageId = null;
      _editingMessageId = message.id;
      _editingOriginalText = message.text;
      _draftText = message.text;
    });
  }

  void _onCancelEdit() {
    if (!mounted) return;
    setState(() {
      _editingMessageId = null;
      _editingOriginalText = null;
      _draftText = '';
    });
  }

  Future<void> _onDeleteMessage(String messageId) async {
    if (!mounted) return;
    final message = _messages.where((m) => m.id == messageId).firstOrNull;
    if (message == null || message.isDeleted) return;

    final action = await _showDeleteMessageSheet(
      canDeleteForEveryone: _canDeleteForEveryone(message),
    );
    if (!mounted || action == null || action == _DeleteMessageAction.cancel) {
      return;
    }

    if (_editingMessageId == messageId) {
      setState(() {
        _editingMessageId = null;
        _editingOriginalText = null;
        _draftText = '';
      });
    }
    if (_activeQuoteMessageId == messageId && mounted) {
      setState(() => _activeQuoteMessageId = null);
    }

    if (action == _DeleteMessageAction.forMe) {
      final deleted = await widget.deleteMessageForMeFn(
        message: message,
        messageRepo: widget.messageRepo,
        reactionRepo: widget.reactionRepo,
        mediaAttachmentRepo: widget.mediaAttachmentRepo,
        mediaFileManager: widget.mediaFileManager,
      );
      if (deleted > 0 && mounted) {
        _removeLocalMessage(messageId);
      }
      return;
    }

    final (result, updatedMessage) = await widget.deleteMessageForEveryoneFn(
      p2pService: widget.p2pService,
      messageRepo: widget.messageRepo,
      originalMessage: message,
      reactionRepo: widget.reactionRepo,
      mediaAttachmentRepo: widget.mediaAttachmentRepo,
      mediaFileManager: widget.mediaFileManager,
      bridge: widget.bridge,
      recipientMlKemPublicKey: _contact.mlKemPublicKey,
    );

    if (!mounted) return;
    if (updatedMessage != null) {
      setState(() => _upsertMessageById(updatedMessage));
      return;
    }
    if (result != SendChatMessageResult.success) {
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.conversation_delete_failed,
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  bool get _canEnterEditMode =>
      _pendingAttachments.isEmpty &&
      !_composerViewState.isProcessing &&
      !_composerViewState.isUploading &&
      !_isRecording &&
      !_isSending;

  bool _canDeleteForEveryone(ConversationMessage message) {
    final ownPeerId = _identity?.peerId;
    if (ownPeerId == null) return false;
    if (message.isIncoming || message.isDeleted) return false;
    if (message.senderPeerId != ownPeerId) return false;
    return message.status == 'delivered';
  }

  Future<_DeleteMessageAction?> _showDeleteMessageSheet({
    required bool canDeleteForEveryone,
  }) {
    return showModalBottomSheet<_DeleteMessageAction>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) =>
          _DeleteMessageSheet(canDeleteForEveryone: canDeleteForEveryone),
    );
  }

  (String?, bool) _resolveActiveQuotePreview() {
    final quoteId = _activeQuoteMessageId;
    if (quoteId == null) return (null, false);

    final quoted = _messages.where((m) => m.id == quoteId).firstOrNull;
    if (quoted == null) return (null, true);
    if (quoted.text.isNotEmpty) return (quoted.text, false);
    if (quoted.media.isNotEmpty) return (mediaPreviewText(quoted.media), false);
    return (null, true);
  }

  void _startListeningForContactUpdates() {
    _contactUpdateSubscription = widget.chatMessageListener.contactUpdatedStream
        .where((c) => c.peerId == _contact.peerId)
        .listen(
          (updatedContact) {
            if (!mounted) return;
            setState(() => _contact = updatedContact);
          },
          onError: (error) {
            emitFlowEvent(
              layer: 'FL',
              event: 'CONV_CONTACT_UPDATE_STREAM_ERROR',
              details: {'error': error.toString()},
            );
          },
          onDone: () {
            emitFlowEvent(
              layer: 'FL',
              event: 'CONV_CONTACT_UPDATE_STREAM_DONE',
              details: {},
            );
          },
        );
  }

  Future<void> _onSend(String text) async {
    final identity = _identity;
    if (identity == null) return;
    final messenger = ScaffoldMessenger.maybeOf(context);

    final hasAttachments = _pendingAttachments.isNotEmpty;
    final sanitizedText = sanitizeMessageText(text);
    final editingMessage = _editingMessageId == null
        ? null
        : _messages.where((m) => m.id == _editingMessageId).firstOrNull;
    if (sanitizedText.isEmpty && !hasAttachments) return;
    if (_isSending) return;

    if (editingMessage != null) {
      final originalText = _editingOriginalText ?? editingMessage.text;
      if (sanitizedText == originalText) {
        if (!mounted) return;
        setState(() {
          _editingMessageId = null;
          _editingOriginalText = null;
          _draftText = '';
        });
        return;
      }

      setState(() => _isSending = true);

      try {
        final (result, message) = await widget.editChatMessageFn(
          p2pService: widget.p2pService,
          messageRepo: widget.messageRepo,
          originalMessage: editingMessage,
          updatedText: sanitizedText,
          senderUsername: identity.username,
          bridge: widget.bridge,
          recipientMlKemPublicKey: _contact.mlKemPublicKey,
          mediaAttachmentRepo: widget.mediaAttachmentRepo,
        );

        if (!mounted) return;

        setState(() {
          _editingMessageId = null;
          _editingOriginalText = null;
          _draftText = '';
          if (message != null) {
            _upsertMessageById(message);
          }
        });

        if (message != null) {
          _scrollToBottom();
        }

        if (result != SendChatMessageResult.success && message == null) {
          messenger
            ?..hideCurrentSnackBar()
            ..showSnackBar(
              const SnackBar(
                content: Text('Failed to save edit.'),
                behavior: SnackBarBehavior.floating,
              ),
            );
        }
      } finally {
        if (mounted) {
          setState(() => _isSending = false);
        }
      }
      return;
    }

    setState(() => _isSending = true);

    try {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONV_FL_SEND_PRESSED',
        details: {
          'textLength': sanitizedText.length,
          'attachments': _pendingAttachments.length,
        },
      );

      final draftText = sanitizedText;
      final quotedMessageId = _activeQuoteMessageId;
      final composerSnapshot = _ComposerSnapshot(
        draftText: draftText,
        quotedMessageId: quotedMessageId,
        pendingAttachments: List<PendingComposerMedia>.from(
          _pendingAttachments,
        ),
      );
      if (_activeQuoteMessageId != null && mounted) {
        setState(() => _activeQuoteMessageId = null);
      }

      // Capture and clear pending attachments
      final mediaToUpload = List<PendingComposerMedia>.from(
        _pendingAttachments,
      );
      List<MediaAttachment>? optimisticMedia;
      List<_PreparedConversationMediaUpload> preparedUploads = const [];

      if (mediaToUpload.isNotEmpty) {
        final now = DateTime.now().toUtc().toIso8601String();
        optimisticMedia = mediaToUpload.map((m) {
          final mime = _mimeFromPath(m.file.path);
          return MediaAttachment(
            id: _uuid.v4(),
            messageId: '',
            mime: mime,
            size: 0,
            mediaType: MediaAttachment.mediaTypeFromMime(mime),
            width: m.width,
            height: m.height,
            durationMs: m.durationMs,
            localPath: m.file.path,
            downloadStatus: 'done',
            createdAt: now,
          );
        }).toList();
      }

      _pendingAttachments = [];
      _draftText = '';
      _updateComposerState(
        pendingAttachments: const [],
        isUploading: mediaToUpload.isNotEmpty,
      );

      final now = DateTime.now().toUtc().toIso8601String();
      final optimisticMessage = ConversationMessage(
        id: _uuid.v4(),
        contactPeerId: _contact.peerId,
        senderPeerId: identity.peerId,
        text: sanitizedText,
        timestamp: now,
        status: 'sending',
        isIncoming: false,
        createdAt: now,
        quotedMessageId: quotedMessageId,
        media: optimisticMedia ?? const [],
      );

      if (mounted) {
        setState(() {
          _upsertMessageById(optimisticMessage);
        });
        _scrollToBottom();
      }

      try {
        await widget.messageRepo.saveMessage(optimisticMessage);
        await _persistOptimisticAttachments(
          optimisticMessage.id,
          optimisticMedia,
          errorEvent: 'CONV_FL_OPTIMISTIC_ATTACHMENT_SAVE_ERROR',
        );
      } catch (e) {
        emitFlowEvent(
          layer: 'FL',
          event: 'CONV_FL_OPTIMISTIC_SAVE_ERROR',
          details: {'error': e.toString()},
        );
      }

      if (mediaToUpload.isNotEmpty &&
          widget.bridge != null &&
          _supportsDurableMediaUploads &&
          optimisticMedia != null) {
        try {
          preparedUploads = await _prepareDurableMediaUploads(
            messageId: optimisticMessage.id,
            mediaToUpload: mediaToUpload,
            optimisticMedia: optimisticMedia,
          );
          if (mounted && preparedUploads.isNotEmpty) {
            final displayMedia = preparedUploads
                .map(
                  (plan) => plan.pendingAttachment.copyWith(
                    localPath: plan.absoluteDurablePath,
                    downloadStatus: 'done',
                  ),
                )
                .toList(growable: false);
            setState(
              () => _upsertMessageById(
                optimisticMessage.copyWith(media: displayMedia),
              ),
            );
          }
        } catch (e) {
          emitFlowEvent(
            layer: 'FL',
            event: 'CONV_FL_MEDIA_DURABLE_PREP_ERROR',
            details: {'error': e.toString()},
          );
          await _restoreComposerSnapshot(
            composerSnapshot,
            optimisticMessageId: optimisticMessage.id,
            messenger: messenger,
            snackText: 'Failed to prepare media. Try again.',
          );
          return;
        }
      }

      // Acquire background task BEFORE upload so iOS cannot suspend during upload.
      final bgTaskId = widget.bridge != null
          ? await callBgBegin(widget.bridge!)
          : null;

      try {
        // Upload attachments if any
        List<MediaAttachment>? uploadedAttachments;
        if (mediaToUpload.isNotEmpty && widget.bridge != null) {
          _beginActiveAttachmentUpload(
            messageId: optimisticMessage.id,
            composerSnapshot: composerSnapshot,
          );
          try {
            uploadedAttachments = [];
            var relayTrackingStarted = false;
            for (var index = 0; index < mediaToUpload.length; index++) {
              if (await _cancelActiveAttachmentUploadIfRequested(
                messenger: messenger,
              )) {
                return;
              }
              final media = mediaToUpload[index];
              final preparedUpload = preparedUploads.length > index
                  ? preparedUploads[index]
                  : null;
              final mime =
                  preparedUpload?.pendingAttachment.mime ??
                  _mimeFromPath(media.file.path);
              final mediaId =
                  preparedUpload?.pendingAttachment.id ??
                  optimisticMedia?[index].id ??
                  _uuid.v4();
              final sourcePath =
                  preparedUpload?.absoluteDurablePath ?? media.file.path;
              final fileSize =
                  preparedUpload?.source.budgetBytes ??
                  File(sourcePath).lengthSync();

              // Try local WiFi first.
              bool localSuccess = false;
              if (widget.p2pService.isLocalPeer(_contact.peerId)) {
                localSuccess = await widget.p2pService.sendLocalMedia(
                  peerId: _contact.peerId,
                  filePath: sourcePath,
                  mime: mime,
                  mediaId: mediaId,
                  fromPeerId: identity.peerId,
                  durationMs: media.durationMs,
                );
              }

              if (localSuccess) {
                if (relayTrackingStarted) {
                  _markRelayUploadCompleted(fileSize);
                }
                final localAttachment = preparedUpload != null
                    ? await _buildLocalSuccessAttachmentFromPlan(
                        messageId: optimisticMessage.id,
                        plan: preparedUpload,
                      )
                    : MediaAttachment(
                        id: mediaId,
                        messageId: optimisticMessage.id,
                        mime: mime,
                        size: fileSize,
                        mediaType: MediaAttachment.mediaTypeFromMime(mime),
                        localPath: media.file.path,
                        downloadStatus: 'done',
                        createdAt: DateTime.now().toUtc().toIso8601String(),
                        width: media.width,
                        height: media.height,
                        durationMs: media.durationMs,
                      );
                if (widget.mediaAttachmentRepo != null) {
                  await widget.mediaAttachmentRepo!.saveAttachment(
                    localAttachment,
                  );
                }
                uploadedAttachments.add(localAttachment);
              } else {
                if (!relayTrackingStarted) {
                  final remainingBytes = mediaToUpload
                      .skip(index)
                      .fold<int>(0, (sum, item) => sum + item.budgetBytes);
                  await _startRelayUploadTracking(remainingBytes);
                  relayTrackingStarted = true;
                }
                _markRelayUploadStarted(mediaId);
                final result = await widget.uploadMediaFn(
                  bridge: widget.bridge!,
                  localFilePath: sourcePath,
                  mime: mime,
                  recipientPeerId: _contact.peerId,
                  mediaFileManager: widget.mediaFileManager,
                  blobId: mediaId,
                  width: preparedUpload?.source.width ?? media.width,
                  height: preparedUpload?.source.height ?? media.height,
                  durationMs:
                      preparedUpload?.source.durationMs ?? media.durationMs,
                );

                if (await _cancelActiveAttachmentUploadIfRequested(
                  messenger: messenger,
                )) {
                  return;
                }

                if (result == null) {
                  if (relayTrackingStarted) {
                    await _stopRelayUploadTracking();
                  }
                  await _restoreComposerSnapshot(
                    composerSnapshot,
                    optimisticMessageId: optimisticMessage.id,
                    messenger: messenger,
                    snackText: 'Failed to upload media. Try again.',
                  );
                  return;
                }
                _markRelayUploadCompleted(fileSize);
                if (preparedUpload != null &&
                    widget.mediaAttachmentRepo != null) {
                  final stableResult =
                      await _finalizeUploadedAttachmentFromPlan(
                        messageId: optimisticMessage.id,
                        plan: preparedUpload,
                        uploaded: result.copyWith(
                          id: mediaId,
                          messageId: optimisticMessage.id,
                          downloadStatus: 'done',
                        ),
                      );
                  await widget.mediaAttachmentRepo!.saveAttachment(
                    stableResult,
                  );
                  uploadedAttachments.add(stableResult);
                } else {
                  uploadedAttachments.add(result);
                }
              }

              if (await _cancelActiveAttachmentUploadIfRequested(
                messenger: messenger,
              )) {
                return;
              }
            }
            if (await _cancelActiveAttachmentUploadIfRequested(
              messenger: messenger,
            )) {
              return;
            }
            if (relayTrackingStarted) {
              await _stopRelayUploadTracking();
            }
            if (await _cancelActiveAttachmentUploadIfRequested(
              messenger: messenger,
            )) {
              return;
            }
            if (mounted) {
              _updateComposerState(isUploading: false);
            }
          } finally {
            _clearActiveAttachmentUpload();
          }
        }

        // Re-read contact from DB to pick up ML-KEM key updates that may
        // have arrived via reciprocal contact request since this screen opened.
        if (widget.contactRepo != null) {
          final fresh = await widget.contactRepo!.getContact(_contact.peerId);
          if (fresh != null && mounted) {
            setState(() => _contact = fresh);
          }
        }

        final (result, message) = await widget.sendChatMessageFn(
          p2pService: widget.p2pService,
          messageRepo: widget.messageRepo,
          targetPeerId: _contact.peerId,
          text: sanitizedText,
          senderPeerId: identity.peerId,
          senderUsername: identity.username,
          messageId: optimisticMessage.id,
          timestamp: optimisticMessage.timestamp,
          bridge: widget.bridge,
          recipientMlKemPublicKey: _contact.mlKemPublicKey,
          quotedMessageId: quotedMessageId,
          mediaAttachments: uploadedAttachments,
          mediaAttachmentRepo: widget.mediaAttachmentRepo,
        );

        if (preparedUploads.isNotEmpty &&
            uploadedAttachments != null &&
            uploadedAttachments.length == mediaToUpload.length) {
          try {
            await widget.mediaFileManager?.deletePendingUploadDir(
              optimisticMessage.id,
            );
          } catch (_) {}
        }

        if (!mounted) return;

        if (message != null) {
          // Resolve relative paths from uploaded attachments to absolute for display
          List<MediaAttachment>? displayMedia;
          if (uploadedAttachments != null && widget.mediaFileManager != null) {
            displayMedia = [];
            for (final a in uploadedAttachments) {
              if (a.localPath != null) {
                final absPath = await widget.mediaFileManager!
                    .resolveStoredPath(a.localPath!);
                displayMedia.add(a.copyWith(localPath: absPath));
              } else {
                displayMedia.add(a);
              }
            }
          }
          final persistedMedia = displayMedia ?? optimisticMedia;
          final messageWithMedia = message.copyWith(
            quotedMessageId: quotedMessageId,
            media: persistedMedia ?? message.media,
          );
          setState(() {
            _upsertMessageById(messageWithMedia);
          });
          _scrollToBottom();
        } else {
          final fallbackStatus = switch (result) {
            SendChatMessageResult.success => 'sent',
            _ => 'failed',
          };
          _updateLocalMessageStatus(optimisticMessage.id, fallbackStatus);
          await _persistMessageStatus(optimisticMessage.id, fallbackStatus);
        }

        if (result != SendChatMessageResult.success) {
          final snackText = switch (result) {
            SendChatMessageResult.nodeNotRunning =>
              'Network not connected. Message saved.',
            SendChatMessageResult.peerNotFound =>
              'Contact appears offline. Message saved.',
            SendChatMessageResult.dialFailed =>
              'Could not connect to contact. Message saved.',
            SendChatMessageResult.invalidMessage => 'Message cannot be empty.',
            SendChatMessageResult.encryptionRequired =>
              'Cannot send: contact does not support encryption.',
            _ => 'Failed to send message. Message saved.',
          };
          await _restoreComposerSnapshot(
            composerSnapshot,
            optimisticMessageId: optimisticMessage.id,
            messenger: messenger,
            snackText: snackText,
            showSnackBar: false,
          );
          messenger?.showSnackBar(
            SnackBar(
              content: Text(snackText),
              backgroundColor: Colors.red[700],
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        emitFlowEvent(
          layer: 'FL',
          event: 'CONV_FL_SEND_ERROR',
          details: {'error': e.toString()},
        );
        if (!mounted) return;
        await _restoreComposerSnapshot(
          composerSnapshot,
          optimisticMessageId: optimisticMessage.id,
          messenger: messenger,
          snackText: 'Failed to send message. Message saved.',
        );
      } finally {
        if (bgTaskId != null && widget.bridge != null) {
          await callBgEnd(widget.bridge!, bgTaskId);
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      } else {
        _isSending = false;
      }
    }
  }

  void _onDraftChanged(String text) {
    if (_draftText == text) return;
    setState(() => _draftText = text);
  }

  Future<void> _onRetryFailedMedia(String messageId) async {
    final bridge = widget.bridge;
    final contactRepo = widget.contactRepo;
    if (bridge == null || contactRepo == null) {
      _showFloatingSnackBar(
        'Retry unavailable right now.',
        backgroundColor: Colors.red[700],
      );
      return;
    }

    final fallbackMedia = _messages
        .where((message) => message.id == messageId)
        .firstOrNull
        ?.media;
    final retried = await retryFailedMessage(
      messageId: messageId,
      messageRepo: widget.messageRepo,
      identityRepo: widget.identityRepo,
      contactRepo: contactRepo,
      p2pService: widget.p2pService,
      bridge: bridge,
      mediaAttachmentRepo: widget.mediaAttachmentRepo,
      uploadMediaFn: widget.uploadMediaFn,
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
    final storedAttachments =
        await mediaAttachmentRepo?.getAttachmentsForMessage(messageId) ??
        const <MediaAttachment>[];
    final storedPaths = storedAttachments.map(
      (attachment) => attachment.localPath,
    );

    await mediaAttachmentRepo?.markUploadPendingAttachmentsFailedForMessage(
      messageId,
    );
    await widget.mediaFileManager?.deleteOwnedPendingUploadFilesForMessage(
      messageId: messageId,
      storedPaths: storedPaths,
    );
    await mediaAttachmentRepo?.deleteAttachmentsForMessage(messageId);
    await widget.messageRepo.deleteMessage(messageId);

    _removeLocalMessage(messageId);
  }

  Future<void> _restoreComposerSnapshot(
    _ComposerSnapshot snapshot, {
    required String optimisticMessageId,
    required ScaffoldMessengerState? messenger,
    required String snackText,
    bool showSnackBar = true,
  }) async {
    _draftText = snapshot.draftText;
    _pendingAttachments = List<PendingComposerMedia>.from(
      snapshot.pendingAttachments,
    );
    _updateComposerState(
      pendingAttachments: _pendingAttachmentFiles(),
      isUploading: false,
    );
    _updateLocalMessageStatus(optimisticMessageId, 'failed');
    await _persistMessageStatus(optimisticMessageId, 'failed');
    await _refreshMessageWithHydratedMedia(optimisticMessageId);
    if (mounted) {
      setState(() => _activeQuoteMessageId = snapshot.quotedMessageId);
    }
    if (showSnackBar) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(snackText),
          backgroundColor: Colors.red[700],
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
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

  void _onAttach() {
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
          } on _RejectedPendingMediaException {
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
        event: 'CONV_FL_PICK_GALLERY_ERROR',
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
        event: 'CONV_FL_PICK_CAMERA_ERROR',
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
        event: 'CONV_FL_PICK_VIDEO_CAMERA_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  // -- Voice recording --

  Future<void> _onRecordStart() async {
    final recorder = widget.audioRecorderService;
    if (recorder == null || _composerViewState.recordingState.isActive) return;

    _pendingRecorderAbort = false;
    _updateComposerState(
      recordingState: VoiceRecordingState.arming,
      recordingDuration: Duration.zero,
      amplitudeValues: const [],
    );

    final hasPermission = await recorder.requestPermission();
    if (!mounted || _pendingRecorderAbort) {
      if (_composerViewState.recordingState != VoiceRecordingState.idle) {
        _updateComposerState(
          recordingState: VoiceRecordingState.idle,
          recordingDuration: Duration.zero,
          amplitudeValues: const [],
        );
      }
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
      // outputPath is handled internally by the recorder service (temp dir)
      await recorder.start(outputPath: '');
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONV_FL_RECORD_START_ERROR',
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

    emitFlowEvent(layer: 'FL', event: 'CONV_FL_RECORD_STARTED', details: {});
  }

  Future<void> _onRecordStop() async {
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

    if (recording == null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONV_FL_RECORD_TOO_SHORT',
        details: {},
      );
      return;
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'CONV_FL_RECORD_STOPPED',
      details: {'durationMs': recording.durationMs},
    );

    // Send the voice message
    final identity = _identity;
    if (identity == null) return;
    final quotedMessageId = _activeQuoteMessageId;
    if (quotedMessageId != null && mounted) {
      setState(() => _activeQuoteMessageId = null);
    }

    final now = DateTime.now().toUtc().toIso8601String();
    final voiceAttachmentId = _uuid.v4();
    final optimisticMessage = ConversationMessage(
      id: _uuid.v4(),
      contactPeerId: _contact.peerId,
      senderPeerId: identity.peerId,
      text: '',
      timestamp: now,
      status: 'sending',
      isIncoming: false,
      createdAt: now,
      quotedMessageId: quotedMessageId,
      media: [
        MediaAttachment(
          id: voiceAttachmentId,
          messageId: '',
          mime: recording.mime,
          size: recording.sizeBytes,
          mediaType: 'audio',
          durationMs: recording.durationMs,
          localPath: recording.filePath,
          downloadStatus: 'done',
          createdAt: now,
          waveform: waveform,
        ),
      ],
    );

    if (mounted) {
      setState(() {
        _upsertMessageById(optimisticMessage);
      });
      _updateComposerState(isUploading: true);
      _scrollToBottom();
    }

    try {
      await widget.messageRepo.saveMessage(optimisticMessage);
      await _persistOptimisticAttachments(
        optimisticMessage.id,
        optimisticMessage.media,
        errorEvent: 'CONV_FL_VOICE_OPTIMISTIC_ATTACHMENT_SAVE_ERROR',
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONV_FL_VOICE_OPTIMISTIC_SAVE_ERROR',
        details: {'error': e.toString()},
      );
    }

    // Re-read contact from DB to pick up ML-KEM key updates.
    if (widget.contactRepo != null) {
      final fresh = await widget.contactRepo!.getContact(_contact.peerId);
      if (fresh != null && mounted) {
        setState(() => _contact = fresh);
      }
    }

    // Acquire background task BEFORE local transfer / relay upload.
    final bgTaskId = widget.bridge != null
        ? await callBgBegin(widget.bridge!)
        : null;

    try {
      // Try local WiFi first for voice messages.
      if (widget.p2pService.isLocalPeer(_contact.peerId)) {
        final localSuccess = await widget.p2pService.sendLocalMedia(
          peerId: _contact.peerId,
          filePath: recording.filePath,
          mime: recording.mime,
          mediaId: voiceAttachmentId,
          fromPeerId: identity.peerId,
          durationMs: recording.durationMs,
          waveform: waveform,
        );

        if (localSuccess) {
          // Voice transferred locally — send text-only message via local WS.
          final voiceAttachment = MediaAttachment(
            id: voiceAttachmentId,
            messageId: optimisticMessage.id,
            mime: recording.mime,
            size: recording.sizeBytes,
            mediaType: 'audio',
            durationMs: recording.durationMs,
            localPath: recording.filePath,
            downloadStatus: 'done',
            createdAt: optimisticMessage.timestamp,
            waveform: waveform,
          );

          final (result, voiceMessage) = await widget.sendChatMessageFn(
            p2pService: widget.p2pService,
            messageRepo: widget.messageRepo,
            targetPeerId: _contact.peerId,
            text: '',
            senderPeerId: identity.peerId,
            senderUsername: identity.username,
            messageId: optimisticMessage.id,
            timestamp: optimisticMessage.timestamp,
            bridge: widget.bridge,
            recipientMlKemPublicKey: _contact.mlKemPublicKey,
            quotedMessageId: quotedMessageId,
            mediaAttachments: [voiceAttachment],
            mediaAttachmentRepo: widget.mediaAttachmentRepo,
          );

          if (mounted) {
            _updateComposerState(isUploading: false);
          }

          if (result == SendChatMessageResult.success && voiceMessage != null) {
            final messageWithMedia = voiceMessage.copyWith(
              media: optimisticMessage.media,
            );
            if (mounted) {
              setState(() => _upsertMessageById(messageWithMedia));
            }
          } else {
            _updateLocalMessageStatus(optimisticMessage.id, 'failed');
            await _persistMessageStatus(optimisticMessage.id, 'failed');
            if (quotedMessageId != null && mounted) {
              setState(() => _activeQuoteMessageId = quotedMessageId);
            }
          }
          return;
        }
      }

      final bridge = widget.bridge;
      if (bridge == null) {
        _updateLocalMessageStatus(optimisticMessage.id, 'failed');
        await _persistMessageStatus(optimisticMessage.id, 'failed');
        if (quotedMessageId != null && mounted) {
          setState(() => _activeQuoteMessageId = quotedMessageId);
        }
        emitFlowEvent(
          layer: 'FL',
          event: 'CONV_FL_VOICE_SEND_NO_BRIDGE',
          details: {},
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(context)!.conversation_voice_fail,
              ),
              backgroundColor: Colors.red[700],
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      // Upload + send (relay fallback)
      await _startRelayUploadTracking(recording.sizeBytes);
      _markRelayUploadStarted(voiceAttachmentId);
      final (result, voiceMessage) = await widget.sendVoiceMessageFn(
        p2pService: widget.p2pService,
        messageRepo: widget.messageRepo,
        targetPeerId: _contact.peerId,
        senderPeerId: identity.peerId,
        senderUsername: identity.username,
        recording: recording,
        bridge: bridge,
        recipientMlKemPublicKey: _contact.mlKemPublicKey,
        mediaAttachmentRepo: widget.mediaAttachmentRepo,
        mediaFileManager: widget.mediaFileManager,
        waveform: waveform,
        messageId: optimisticMessage.id,
        timestamp: optimisticMessage.timestamp,
        quotedMessageId: quotedMessageId,
        blobId: voiceAttachmentId,
      );
      if (result != SendVoiceMessageResult.uploadFailed) {
        _markRelayUploadCompleted(recording.sizeBytes);
      }
      await _stopRelayUploadTracking();

      if (mounted) {
        _updateComposerState(isUploading: false);
      }

      if (result == SendVoiceMessageResult.success && voiceMessage != null) {
        // Replace optimistic with real message, preserving local media for playback.
        // DB already has correct data from sendChatMessage's saveMessage call.
        final messageWithMedia = voiceMessage.copyWith(
          media: optimisticMessage.media,
        );
        if (mounted) {
          setState(() {
            _upsertMessageById(messageWithMedia);
          });
        }
      } else if (result == SendVoiceMessageResult.success) {
        _updateLocalMessageStatus(optimisticMessage.id, 'sent');
        await _persistMessageStatus(optimisticMessage.id, 'sent');
      } else {
        _updateLocalMessageStatus(optimisticMessage.id, 'failed');
        await _persistMessageStatus(optimisticMessage.id, 'failed');
        if (quotedMessageId != null && mounted) {
          setState(() => _activeQuoteMessageId = quotedMessageId);
        }

        if (mounted) {
          final snackText = switch (result) {
            SendVoiceMessageResult.uploadFailed =>
              'Failed to upload voice message. Try again.',
            _ => AppLocalizations.of(context)!.conversation_voice_fail,
          };
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(snackText),
              backgroundColor: Colors.red[700],
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } finally {
      await _stopRelayUploadTracking();
      if (bgTaskId != null && widget.bridge != null) {
        await callBgEnd(widget.bridge!, bgTaskId);
      }
    }
  }

  Future<void> _onRecordCancel() async {
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

    emitFlowEvent(layer: 'FL', event: 'CONV_FL_RECORD_CANCELLED', details: {});
  }

  void _startListeningForReactions() {
    final listener = widget.reactionListener;
    if (listener == null) return;

    _reactionSubscription = listener.incomingReactionChangeStream
        .where((change) {
          // Only process reactions for messages in this conversation
          return _messages.any((m) => m.id == change.messageId);
        })
        .listen(
          _onIncomingReactionChange,
          onError: (error) {
            emitFlowEvent(
              layer: 'FL',
              event: 'CONV_REACTION_STREAM_ERROR',
              details: {'error': error.toString()},
            );
          },
        );
  }

  void _onIncomingReactionChange(ReactionChange change) {
    if (!mounted) return;
    setState(() {
      final messageReactions = List<MessageReaction>.from(
        _reactions[change.messageId] ?? [],
      );

      if (change.type == ReactionChangeType.removed) {
        messageReactions.removeWhere(
          (reaction) => reaction.senderPeerId == change.senderPeerId,
        );
      } else if (change.reaction != null) {
        final idx = messageReactions.indexWhere(
          (reaction) => reaction.senderPeerId == change.senderPeerId,
        );
        if (idx >= 0) {
          messageReactions[idx] = change.reaction!;
        } else {
          messageReactions.add(change.reaction!);
        }
      }
      _reactions = {..._reactions, change.messageId: messageReactions};
    });
  }

  Future<void> _loadReactions(List<ConversationMessage> messages) async {
    final reactionRepo = widget.reactionRepo;
    if (reactionRepo == null || messages.isEmpty) return;

    try {
      final messageIds = messages.map((m) => m.id).toList();
      final reactions = await loadReactionsForConversation(
        reactionRepo: reactionRepo,
        messageIds: messageIds,
      );
      if (mounted) {
        setState(() => _reactions = reactions);
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONV_FL_LOAD_REACTIONS_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _onReactionSelected(String messageId, String emoji) async {
    final identity = _identity;
    if (identity == null) return;

    final reactionRepo = widget.reactionRepo;
    final bridge = widget.bridge;
    if (reactionRepo == null || bridge == null) return;

    // Check if toggling (same emoji from same user)
    final existingReactions = _reactions[messageId] ?? [];
    final ownReaction = existingReactions
        .where((r) => r.senderPeerId == identity.peerId)
        .firstOrNull;

    if (ownReaction != null && ownReaction.emoji == emoji) {
      // Toggle off: remove reaction
      setState(() {
        final updated = existingReactions
            .where((r) => r.senderPeerId != identity.peerId)
            .toList();
        _reactions = {..._reactions, messageId: updated};
      });

      await removeReaction(
        p2pService: widget.p2pService,
        bridge: bridge,
        reactionRepo: reactionRepo,
        targetPeerId: _contact.peerId,
        messageId: messageId,
        emoji: emoji,
        senderPeerId: identity.peerId,
        recipientMlKemPublicKey: _contact.mlKemPublicKey ?? '',
      );
      return;
    }

    // Add/replace reaction optimistically
    final now = DateTime.now().toUtc().toIso8601String();
    final optimisticReaction = MessageReaction(
      id: '',
      messageId: messageId,
      emoji: emoji,
      senderPeerId: identity.peerId,
      timestamp: now,
      createdAt: now,
    );

    setState(() {
      final updated = List<MessageReaction>.from(existingReactions);
      final idx = updated.indexWhere((r) => r.senderPeerId == identity.peerId);
      if (idx >= 0) {
        updated[idx] = optimisticReaction;
      } else {
        updated.add(optimisticReaction);
      }
      _reactions = {..._reactions, messageId: updated};
    });

    final (result, reaction) = await sendReaction(
      p2pService: widget.p2pService,
      bridge: bridge,
      reactionRepo: reactionRepo,
      targetPeerId: _contact.peerId,
      messageId: messageId,
      emoji: emoji,
      senderPeerId: identity.peerId,
      recipientMlKemPublicKey: _contact.mlKemPublicKey ?? '',
    );

    // Update with real reaction on success
    if (result == SendReactionResult.success && reaction != null && mounted) {
      setState(() {
        final updated = List<MessageReaction>.from(_reactions[messageId] ?? []);
        final idx = updated.indexWhere(
          (r) => r.senderPeerId == identity.peerId,
        );
        if (idx >= 0) {
          updated[idx] = reaction;
        }
        _reactions = {..._reactions, messageId: updated};
      });
    }
  }

  void _removeAttachment(int index) {
    if (index < 0 || index >= _pendingAttachments.length) return;
    final updated = List<PendingComposerMedia>.from(_pendingAttachments);
    updated.removeAt(index);
    _pendingAttachments = updated;
    _updateComposerState(pendingAttachments: _pendingAttachmentFiles());
  }

  List<File> _pendingAttachmentFiles() {
    return _pendingAttachments
        .map((media) => media.file)
        .toList(growable: false);
  }

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
    for (var i = 0; i < a.length; i++) {
      if (a[i].path != b[i].path) return false;
    }
    return true;
  }

  void _upsertMessageById(ConversationMessage message) {
    if (message.isHidden) {
      _messages = _messages
          .where((existing) => existing.id != message.id)
          .toList();
      return;
    }
    final index = _messages.indexWhere((m) => m.id == message.id);
    if (index == -1) {
      _messages = [..._messages, message];
      return;
    }
    final updated = [..._messages];
    updated[index] = message;
    _messages = updated;
  }

  void _updateLocalMessageStatus(String id, String status) {
    if (!mounted) return;
    setState(() {
      final index = _messages.indexWhere((m) => m.id == id);
      if (index == -1) return;
      final updated = [..._messages];
      updated[index] = updated[index].copyWith(status: status);
      _messages = updated;
    });
  }

  void _removeLocalMessage(String id) {
    if (!mounted) return;
    setState(() {
      _messages = _messages.where((message) => message.id != id).toList();
    });
  }

  Future<void> _persistMessageStatus(String id, String status) async {
    try {
      await widget.messageRepo.updateMessageStatus(id, status);
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONV_FL_STATUS_UPDATE_ERROR',
        details: {'error': e.toString(), 'status': status},
      );
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

  Future<void> _persistOptimisticAttachments(
    String messageId,
    List<MediaAttachment>? attachments, {
    required String errorEvent,
  }) async {
    final mediaAttachmentRepo = widget.mediaAttachmentRepo;
    if (mediaAttachmentRepo == null ||
        attachments == null ||
        attachments.isEmpty) {
      return;
    }

    try {
      for (final attachment in attachments) {
        await mediaAttachmentRepo.saveAttachment(
          attachment.copyWith(
            messageId: messageId,
            downloadStatus: 'upload_pending',
          ),
        );
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: errorEvent,
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _refreshMessageWithHydratedMedia(
    String messageId, {
    List<MediaAttachment>? fallbackMedia,
  }) async {
    final refreshedMessage = await widget.messageRepo.getMessage(messageId);
    if (refreshedMessage == null || !mounted) return;
    final hydratedMedia = await _resolveHydratedMediaForMessage(
      messageId,
      fallbackMedia: fallbackMedia,
    );
    if (!mounted) return;
    setState(() {
      _upsertMessageById(refreshedMessage.copyWith(media: hydratedMedia));
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

    final mediaFileManager = widget.mediaFileManager;
    if (mediaFileManager == null) {
      return attachments;
    }

    final resolved = <MediaAttachment>[];
    for (final attachment in attachments) {
      resolved.add(await _resolveAttachmentForDisplay(attachment));
    }
    return resolved;
  }

  void _onOverflow() {
    final contactRepo = widget.contactRepo;
    if (contactRepo == null) return;

    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box == null) return;

    // Position the popup menu near the top-right overflow button area
    final topPadding = MediaQuery.of(context).padding.top;
    final position = RelativeRect.fromLTRB(
      box.size.width - 200,
      topPadding + 50,
      16,
      0,
    );

    showMenu<String>(
      context: context,
      position: position,
      color: const Color.fromRGBO(18, 20, 28, 0.98),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color.fromRGBO(255, 255, 255, 0.14)),
      ),
      items: [
        if (!_contact.isBlocked && _hasOtherFriends)
          const PopupMenuItem<String>(
            value: 'introduce',
            child: Row(
              children: [
                Icon(Icons.people_outline, size: 18, color: Color(0xFF10B981)),
                SizedBox(width: 10),
                Text(
                  'Introduce to your circle',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF10B981),
                  ),
                ),
              ],
            ),
          ),
        PopupMenuItem<String>(
          value: 'block',
          child: Row(
            children: [
              Icon(
                _contact.isBlocked ? Icons.replay : Icons.block,
                size: 18,
                color: _contact.isBlocked
                    ? const Color(0xFF10B981)
                    : const Color(0xFFEF4444),
              ),
              const SizedBox(width: 10),
              Text(
                _contact.isBlocked
                    ? 'Unblock ${_contact.username}'
                    : 'Block ${_contact.username}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: _contact.isBlocked
                      ? const Color(0xFF10B981)
                      : const Color(0xFFEF4444),
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'delete',
          child: const Row(
            children: [
              Icon(Icons.delete_outline, size: 18, color: Color(0xFFEF4444)),
              SizedBox(width: 10),
              Text(
                'Delete chat',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFFEF4444),
                ),
              ),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'introduce') {
        _onIntroduce();
      } else if (value == 'block') {
        if (_contact.isBlocked) {
          _onUnblock();
        } else {
          _onBlock();
        }
      } else if (value == 'delete') {
        _onDelete();
      }
    });
  }

  Future<void> _onBlock() async {
    final contactRepo = widget.contactRepo;
    if (contactRepo == null) return;

    final confirmed = await showConfirmationDialog(
      context: context,
      title: AppLocalizations.of(
        context,
      )!.conversation_block(_contact.username),
      description:
          'They won\'t be able to send you messages. You can unblock them later.',
      confirmLabel: 'Block',
    );
    if (!confirmed || !mounted) return;

    try {
      await blockContact(contactRepo: contactRepo, peerId: _contact.peerId);
      if (!mounted) return;
      final updated = await contactRepo.getContact(_contact.peerId);
      if (updated != null && mounted) {
        setState(() => _contact = updated);
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONV_FL_BLOCK_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _onUnblock() async {
    final contactRepo = widget.contactRepo;
    if (contactRepo == null) return;

    try {
      await unblockContact(contactRepo: contactRepo, peerId: _contact.peerId);
      if (!mounted) return;
      final updated = await contactRepo.getContact(_contact.peerId);
      if (updated != null && mounted) {
        setState(() => _contact = updated);
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONV_FL_UNBLOCK_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _onDelete() async {
    final contactRepo = widget.contactRepo;
    if (contactRepo == null) return;

    final confirmed = await showConfirmationDialog(
      context: context,
      title: AppLocalizations.of(context)!.conversation_delete_chat,
      description:
          'This will permanently remove ${_contact.username} and all messages. This cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (!confirmed || !mounted) return;

    try {
      final deleteContactFn = widget.deleteContactFn;
      if (deleteContactFn != null) {
        await deleteContactFn(_contact.peerId);
      } else {
        await deleteContactAndMessages(
          contactRepo: contactRepo,
          messageRepo: widget.messageRepo,
          peerId: _contact.peerId,
          mediaAttachmentRepo: widget.mediaAttachmentRepo,
          reactionRepo: widget.reactionRepo,
          mediaFileManager: widget.mediaFileManager,
          introductionRepo: widget.introductionRepository,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONV_FL_DELETE_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _formatConnectionDate() {
    try {
      final date = DateTime.parse(_contact.scannedAt);
      final locale = Localizations.localeOf(context).toString();
      return intl.DateFormat.yMMMd(locale).format(date);
    } catch (_) {
      return '';
    }
  }

  @override
  void dispose() {
    widget.conversationTracker?.clear();
    _scrollController.removeListener(_onScroll);
    _incomingSubscription?.cancel();
    _repoChangeSubscription?.cancel();
    _contactUpdateSubscription?.cancel();
    _reactionSubscription?.cancel();
    _mediaUploadProgressSubscription?.cancel();
    _durationSub?.cancel();
    _amplitudeSub?.cancel();
    // Cancel active recording on dispose
    if (_isRecording) {
      widget.audioRecorderService?.cancel();
    }
    _composerState.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (activeQuoteText, isActiveQuoteUnavailable) =
        _resolveActiveQuotePreview();

    return PopScope(
      canPop: !_isTrackingRelayUpload || _allowPopDuringActiveUpload,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || !_isTrackingRelayUpload) return;
        unawaited(_handleBackNavigation());
      },
      child: Scaffold(
        body: ConversationScreen(
          contactPeerId: _contact.peerId,
          contactUsername: _contact.username,
          connectionDate: _formatConnectionDate(),
          ownPeerId: _identity?.peerId,
          messages: _messages,
          onSend: _onSend,
          onBack: _handleBackNavigation,
          scrollController: _scrollController,
          isBlocked: _contact.isBlocked,
          onUnblock: _onUnblock,
          onOverflow: widget.contactRepo != null ? _onOverflow : null,
          isLoadingMore: _isLoadingMore,
          hasMoreOlderMessages: _hasMoreOlderMessages,
          initialLoadDone: _initialLoadDone,
          isSending: _isSending,
          recordingState: _composerViewState.recordingState,
          onAttach: _onAttach,
          onRemoveAttachment: _removeAttachment,
          onRecordStart: widget.audioRecorderService != null
              ? _onRecordStart
              : null,
          onRecordStop: widget.audioRecorderService != null
              ? _onRecordStop
              : null,
          onRecordCancel: widget.audioRecorderService != null
              ? _onRecordCancel
              : null,
          composerStateListenable: _composerState,
          initialText: _draftText,
          onDraftChanged: _onDraftChanged,
          reactions: _reactions,
          onReactionSelected: widget.reactionRepo != null
              ? _onReactionSelected
              : null,
          onRetryFailedMedia: _onRetryFailedMedia,
          onDeleteFailedMedia: _onDeleteFailedMedia,
          showIntroBanner: _showIntroBanner,
          bannerContactUsername: _contact.username,
          uploadProgress: _uploadProgressViewState,
          onCancelUpload:
              _activeAttachmentUpload == null ||
                  _activeAttachmentUpload!.cancelRequested
              ? null
              : _requestCancelActiveAttachmentUpload,
          onMakeIntroductions: _onMakeIntroductions,
          onMaybeLater: _onMaybeLater,
          onQuoteReply: _onQuoteReply,
          onDeleteMessage: _onDeleteMessage,
          activeQuoteText: activeQuoteText,
          isActiveQuoteUnavailable: isActiveQuoteUnavailable,
          onClearQuote: _onClearQuote,
          onEditMessage: _onEditMessage,
          isEditingMessage: _editingMessageId != null,
          onCancelEdit: _editingMessageId != null ? _onCancelEdit : null,
          allowEditAction: _canEnterEditMode,
        ),
      ),
    );
  }
}

enum _DeleteMessageAction { forMe, forEveryone, cancel }

class _DeleteMessageSheet extends StatelessWidget {
  final bool canDeleteForEveryone;

  const _DeleteMessageSheet({required this.canDeleteForEveryone});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final maxHeight = MediaQuery.of(context).size.height * 0.72;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              key: ConversationWired.deleteSheetKey,
              decoration: BoxDecoration(
                color: const Color.fromRGBO(18, 20, 28, 0.96),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: const Color.fromRGBO(255, 255, 255, 0.10),
                ),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 42,
                          height: 4,
                          decoration: BoxDecoration(
                            color: const Color.fromRGBO(255, 255, 255, 0.18),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        l10n.conversation_delete_message_prompt,
                        key: ConversationWired.deletePromptKey,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Color.fromRGBO(255, 255, 255, 0.94),
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _DeleteSheetAction(
                        key: ConversationWired.deleteForMeKey,
                        label: l10n.conversation_delete_for_me,
                        icon: Icons.delete_outline_rounded,
                        color: const Color(0xFFFF8A80),
                        onTap: () => Navigator.of(
                          context,
                        ).pop(_DeleteMessageAction.forMe),
                      ),
                      if (canDeleteForEveryone) ...[
                        const SizedBox(height: 10),
                        _DeleteSheetAction(
                          key: ConversationWired.deleteForEveryoneKey,
                          label: l10n.conversation_delete_for_everyone,
                          icon: Icons.person_remove_alt_1_rounded,
                          color: const Color(0xFFFFB38A),
                          onTap: () => Navigator.of(
                            context,
                          ).pop(_DeleteMessageAction.forEveryone),
                        ),
                      ],
                      const SizedBox(height: 10),
                      _DeleteSheetAction(
                        key: ConversationWired.deleteCancelKey,
                        label: l10n.conversation_delete_cancel,
                        icon: Icons.close_rounded,
                        color: const Color.fromRGBO(255, 255, 255, 0.72),
                        onTap: () => Navigator.of(
                          context,
                        ).pop(_DeleteMessageAction.cancel),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DeleteSheetAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _DeleteSheetAction({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: const Color.fromRGBO(255, 255, 255, 0.05),
            border: Border.all(
              color: const Color.fromRGBO(255, 255, 255, 0.08),
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ComposerSnapshot {
  final String draftText;
  final String? quotedMessageId;
  final List<PendingComposerMedia> pendingAttachments;

  const _ComposerSnapshot({
    required this.draftText,
    required this.quotedMessageId,
    required this.pendingAttachments,
  });
}

class _ActiveAttachmentUpload {
  final String messageId;
  final _ComposerSnapshot composerSnapshot;
  final bool cancelRequested;

  const _ActiveAttachmentUpload({
    required this.messageId,
    required this.composerSnapshot,
    this.cancelRequested = false,
  });

  _ActiveAttachmentUpload copyWith({bool? cancelRequested}) {
    return _ActiveAttachmentUpload(
      messageId: messageId,
      composerSnapshot: composerSnapshot,
      cancelRequested: cancelRequested ?? this.cancelRequested,
    );
  }
}
