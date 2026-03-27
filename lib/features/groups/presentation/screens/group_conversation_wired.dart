import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/media/amplitude_buffer.dart';
import 'package:flutter_app/core/media/audio_recorder_service.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/media/downsample_waveform.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_picker.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/constants/retry_constants.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/download_media_use_case.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/compose_area.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/conversation/application/load_reactions_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_change.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/groups/application/remove_group_reaction_use_case.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/application/send_group_reaction_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_screen.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_info_wired.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/settings/domain/models/image_quality_preference.dart';
import 'package:flutter_app/shared/widgets/media/full_screen_image_viewer.dart';
import 'package:flutter_app/shared/widgets/media/media_preview_text.dart';

/// A pending media attachment with optional video metadata.
class _PendingMedia {
  final File file;
  final int? width;
  final int? height;
  final int? durationMs;

  const _PendingMedia({
    required this.file,
    this.width,
    this.height,
    this.durationMs,
  });
}

class _PreparedGroupMediaUpload {
  final _PendingMedia source;
  final MediaAttachment pendingAttachment;
  final String absoluteDurablePath;

  const _PreparedGroupMediaUpload({
    required this.source,
    required this.pendingAttachment,
    required this.absoluteDurablePath,
  });
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
  final List<File>? initialAttachments;
  final String? initialText;
  final ReactionRepository? reactionRepo;
  final UploadMediaFn uploadMediaFn;

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
    this.initialAttachments,
    this.initialText,
    this.reactionRepo,
    this.uploadMediaFn = uploadMedia,
  });

  @override
  State<GroupConversationWired> createState() => _GroupConversationWiredState();
}

class _GroupConversationWiredState extends State<GroupConversationWired> {
  static const _maxAttachments = 10;
  static const _liveEdgeTolerance = 32.0;
  static final MediaPicker _defaultMediaPicker = SystemMediaPicker();

  List<GroupMessage> _messages = [];
  String? _ownPeerId;
  String _senderUsername = '';
  String _senderPublicKey = '';
  String _senderPrivateKey = '';
  StreamSubscription<GroupMessage>? _messageSubscription;
  final ScrollController _scrollController = ScrollController();
  bool _initialLoadDone = false;
  bool _isSending = false;
  String? _activeQuoteMessageId;
  String _draftText = '';

  // Media state
  List<_PendingMedia> _pendingAttachments = [];
  final _composerState = ValueNotifier(const ConversationComposerViewState());
  Map<String, List<MediaAttachment>> _mediaMap = {};

  // Reaction state
  Map<String, List<MessageReaction>> _reactions = {};
  StreamSubscription<ReactionChange>? _reactionSubscription;

  // Voice recording state
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<double>? _amplitudeSub;
  final _amplitudeBuffer = AmplitudeBuffer(size: 25);
  List<double> _waveformSamples = [];
  bool _pendingRecorderAbort = false;

  ConversationComposerViewState get _composerViewState => _composerState.value;

  MediaPicker get _mediaPicker => widget.mediaPicker ?? _defaultMediaPicker;

  bool get _isRecording => _composerViewState.recordingState.isActive;

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
    _draftText = widget.initialText ?? '';
    widget.groupConversationTracker?.setActive('group:${widget.group.id}');
    if (widget.initialAttachments != null &&
        widget.initialAttachments!.isNotEmpty) {
      _pendingAttachments = widget.initialAttachments!
          .map((f) => _PendingMedia(file: f))
          .toList();
      _updateComposerState(pendingAttachments: _pendingAttachmentFiles());
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
    _loadMessages();
    _startListening();
    _startListeningForReactions();
  }

  @override
  void didUpdateWidget(covariant GroupConversationWired oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldCanWrite = _canWriteForGroup(oldWidget.group);
    final newCanWrite = _canWriteForGroup(widget.group);
    if (oldCanWrite && !newCanWrite && _activeQuoteMessageId != null) {
      _activeQuoteMessageId = null;
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
        if (attachment.downloadStatus == 'pending') {
          final downloaded = await downloadMedia(
            bridge: widget.bridge,
            mediaAttachmentRepo: widget.mediaAttachmentRepo!,
            mediaFileManager: widget.mediaFileManager!,
            attachment: attachment,
            contactPeerId: widget.group.id,
          );
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
  }

  void _startListening() {
    _messageSubscription = widget.groupMessageListener.groupMessageStream
        .listen(
          (message) {
            if (message.groupId == widget.group.id) {
              unawaited(_applyMessageUpdate(message));
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
  }

  static const _uuid = Uuid();

  bool get _supportsDurableGroupMediaUploads =>
      widget.mediaAttachmentRepo != null && widget.mediaFileManager != null;

  Future<List<_PreparedGroupMediaUpload>> _prepareDurableGroupMediaUploads({
    required String messageId,
    required List<_PendingMedia> mediaToUpload,
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

    final uploadResults = await Future.wait(
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
        try {
          return await widget.uploadMediaFn(
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

    final completedAttachments = <MediaAttachment>[];
    final failedPlans = <_PreparedGroupMediaUpload>[];

    for (var index = 0; index < uploadResults.length; index++) {
      final plan = preparedUploads[index];
      final uploaded = uploadResults[index];

      if (uploaded == null) {
        failedPlans.add(plan);
        continue;
      }

      final completed = uploaded.copyWith(
        id: plan.pendingAttachment.id,
        messageId: messageId,
        downloadStatus: 'done',
        uploadRetryCount: plan.pendingAttachment.uploadRetryCount,
      );
      await mediaAttachmentRepo.saveAttachment(completed);
      completedAttachments.add(completed);
    }

    if (failedPlans.isNotEmpty) {
      final failedIds = failedPlans
          .map((plan) => plan.pendingAttachment.id)
          .toSet();
      for (final plan in preparedUploads) {
        final isFailed = failedIds.contains(plan.pendingAttachment.id);
        final nextRetryCount = isFailed
            ? (plan.pendingAttachment.uploadRetryCount ?? 0) + 1
            : plan.pendingAttachment.uploadRetryCount;
        await mediaAttachmentRepo.saveAttachment(
          plan.pendingAttachment.copyWith(
            downloadStatus:
                isFailed &&
                    nextRetryCount != null &&
                    nextRetryCount >= kMaxUploadRetries
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
      pendingAttachments: List<_PendingMedia>.from(_pendingAttachments),
    );

    // 1. Generate IDs upfront for optimistic display
    final messageId = _uuid.v4();
    final now = DateTime.now().toUtc();

    // 2. Capture and clear pending attachments
    final mediaToUpload = List<_PendingMedia>.from(_pendingAttachments);
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
        final members = await widget.groupRepo.getMembers(widget.group.id);
        final allowedPeers = members.map((m) => m.peerId).toList();

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
          for (var index = 0; index < mediaToUpload.length; index++) {
            final pending = mediaToUpload[index];
            final mime = _mimeFromPath(pending.file.path);
            final attachmentId = optimisticMedia[index].id;
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
              uploadedAttachments.add(
                result.copyWith(
                  id: attachmentId,
                  messageId: messageId,
                  downloadStatus: 'done',
                ),
              );
            } else {
              await _restoreComposerSnapshot(composerSnapshot, messageId);
              return;
            }
          }
          if (mounted) {
            _updateComposerState(isUploading: false);
          }
        }
      } else {
        showOptimisticMessage();
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
      } else if (prePersistedOrdinaryMediaRow &&
          (result == SendGroupMessageResult.groupNotFound ||
              result == SendGroupMessageResult.unauthorized)) {
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
          await widget.msgRepo.deleteMessage(messageId);
        } catch (_) {}
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

  Future<void> _restoreComposerSnapshot(
    _GroupComposerSnapshot snapshot,
    String messageId,
  ) async {
    if (mounted) {
      setState(() {
        _draftText = snapshot.draftText;
        _pendingAttachments = List<_PendingMedia>.from(
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
      resolved.add(attachment.copyWith(localPath: absolutePath));
    }
    return resolved;
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
      final media = <_PendingMedia>[];
      for (final xf in selectedFiles) {
        final result = await _processMediaIfNeeded(xf.path);
        media.add(result);
      }
      if (!mounted) return;
      _pendingAttachments = [..._pendingAttachments, ...media];
      _updateComposerState(pendingAttachments: _pendingAttachmentFiles());
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
      final result = await _processMediaIfNeeded(picked.path);
      if (!mounted) return;
      _pendingAttachments = [..._pendingAttachments, result];
      _updateComposerState(pendingAttachments: _pendingAttachmentFiles());
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
      final result = await _processMediaIfNeeded(picked.path);
      if (!mounted) return;
      _pendingAttachments = [..._pendingAttachments, result];
      _updateComposerState(pendingAttachments: _pendingAttachmentFiles());
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_CONV_FL_PICK_VIDEO_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<_PendingMedia> _processMediaIfNeeded(String path) async {
    final processor = widget.imageProcessor;
    if (processor == null) return _PendingMedia(file: File(path));

    if (processor.isProcessableVideo(path)) {
      _updateComposerState(isProcessing: true, processingProgress: 0.0);
      try {
        final result = await processor.processVideo(
          inputPath: path,
          quality: widget.videoQualityPreference,
          onProgress: (progress) {
            if (mounted) {
              _updateComposerState(processingProgress: progress / 100.0);
            }
          },
        );
        return _PendingMedia(
          file: File(result.path),
          width: result.width,
          height: result.height,
          durationMs: result.durationMs,
        );
      } finally {
        if (mounted) {
          _updateComposerState(isProcessing: false, processingProgress: 0.0);
        }
      }
    }

    final processed = await processor.processImage(
      inputPath: path,
      quality: widget.qualityPreference,
    );
    return _PendingMedia(file: File(processed));
  }

  void _removeAttachment(int index) {
    if (index < 0 || index >= _pendingAttachments.length) return;
    final updated = List<_PendingMedia>.from(_pendingAttachments);
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
    setState(() {
      final idx = _messages.indexWhere((m) => m.id == messageId);
      if (idx >= 0) {
        final updated = List<GroupMessage>.from(_messages);
        updated[idx] = updated[idx].copyWith(status: status);
        _messages = updated;
      }
    });
  }

  void _removeLocalMessage(String messageId) {
    setState(() {
      _messages = _messages
          .where((message) => message.id != messageId)
          .toList();
      final nextMedia = Map<String, List<MediaAttachment>>.from(_mediaMap);
      nextMedia.remove(messageId);
      _mediaMap = nextMedia;
    });
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
          } else {
            _updateLocalMessageStatus(messageId, 'failed');
            await _persistMessageStatus(messageId, 'failed');
            _restoreActiveQuoteIfNeeded(quotedMessageId);
          }
        } catch (_) {}
      } finally {
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

  void _onBack() {
    Navigator.of(context).pop();
  }

  void _onInfo() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GroupInfoWired(
          group: widget.group,
          groupRepo: widget.groupRepo,
          contactRepo: widget.contactRepo,
          bridge: widget.bridge,
          identityRepo: widget.identityRepo,
          p2pService: widget.p2pService,
        ),
      ),
    );
  }

  bool _canWriteForGroup(GroupModel group) {
    if (group.type == GroupType.announcement &&
        group.myRole != GroupRole.admin) {
      return false;
    }
    return true;
  }

  bool get _canWrite => _canWriteForGroup(widget.group);

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
    if (widget.reactionRepo == null) return;
    if (_ownPeerId == null) return;

    // Check if we already have a reaction with this emoji — toggle off
    final existing = (_reactions[messageId] ?? []).where(
      (r) => r.senderPeerId == _ownPeerId && r.emoji == emoji,
    );

    if (existing.isNotEmpty) {
      // Optimistic remove
      setState(() {
        final list = List<MessageReaction>.from(_reactions[messageId] ?? []);
        list.removeWhere((r) => r.senderPeerId == _ownPeerId);
        _reactions = {..._reactions, messageId: list};
      });

      await removeGroupReaction(
        bridge: widget.bridge,
        groupRepo: widget.groupRepo,
        reactionRepo: widget.reactionRepo!,
        groupId: widget.group.id,
        messageId: messageId,
        emoji: emoji,
        senderPeerId: _ownPeerId!,
        senderPublicKey: _senderPublicKey,
        senderPrivateKey: _senderPrivateKey,
      );
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
    }
  }

  @override
  void dispose() {
    widget.groupConversationTracker?.clear();
    _messageSubscription?.cancel();
    _reactionSubscription?.cancel();
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

    return GroupConversationScreen(
      group: widget.group,
      messages: _messages,
      ownPeerId: _ownPeerId,
      onSend: _onSend,
      onBack: _onBack,
      onInfo: _onInfo,
      canWrite: _canWrite,
      isSending: _isSending,
      initialLoadDone: _initialLoadDone,
      scrollController: _scrollController,
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
      onReactionSelected: widget.reactionRepo != null
          ? _onReactionSelected
          : null,
      initialText: _draftText,
      onDraftChanged: _onDraftChanged,
      onQuoteReply: _canWrite ? _onQuoteReply : null,
      activeQuoteText: activeQuoteText,
      isActiveQuoteUnavailable: isActiveQuoteUnavailable,
      onClearQuote: _canWrite ? _onClearQuote : null,
    );
  }
}

class _GroupComposerSnapshot {
  final String draftText;
  final String? quotedMessageId;
  final List<_PendingMedia> pendingAttachments;

  const _GroupComposerSnapshot({
    required this.draftText,
    required this.quotedMessageId,
    required this.pendingAttachments,
  });
}
