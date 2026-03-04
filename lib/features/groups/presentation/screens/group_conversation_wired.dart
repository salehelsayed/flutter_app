import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/media/amplitude_buffer.dart';
import 'package:flutter_app/core/media/audio_recorder_service.dart';
import 'package:flutter_app/core/media/downsample_waveform.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/download_media_use_case.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_screen.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_info_wired.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/settings/domain/models/image_quality_preference.dart';
import 'package:flutter_app/shared/widgets/media/full_screen_image_viewer.dart';

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
  final ImageQualityPreference qualityPreference;
  final ImageQualityPreference videoQualityPreference;
  final AudioRecorderService? audioRecorderService;

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
    this.qualityPreference = ImageQualityPreference.compressed,
    this.videoQualityPreference = ImageQualityPreference.compressed,
    this.audioRecorderService,
  });

  @override
  State<GroupConversationWired> createState() => _GroupConversationWiredState();
}

class _GroupConversationWiredState extends State<GroupConversationWired> {
  static const _uuid = Uuid();
  static const _maxAttachments = 10;

  List<GroupMessage> _messages = [];
  String? _ownPeerId;
  String _senderUsername = '';
  String _senderPublicKey = '';
  String _senderPrivateKey = '';
  StreamSubscription<GroupMessage>? _messageSubscription;
  final ScrollController _scrollController = ScrollController();

  // Media state
  List<_PendingMedia> _pendingAttachments = [];
  bool _isUploading = false;
  bool _isProcessingVideo = false;
  double _processingProgress = 0.0;
  Map<String, List<MediaAttachment>> _mediaMap = {};

  // Voice recording state
  bool _isRecording = false;
  Duration _recordingDuration = Duration.zero;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<double>? _amplitudeSub;
  final _amplitudeBuffer = AmplitudeBuffer(size: 25);
  List<double> _amplitudeValues = const [];
  List<double> _waveformSamples = [];

  @override
  void initState() {
    super.initState();
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
  }

  Future<void> _loadIdentity() async {
    try {
      final identity = await widget.identityRepo.loadIdentity();
      if (identity != null && mounted) {
        setState(() {
          _ownPeerId = identity.peerId;
          _senderUsername = identity.username ?? '';
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

      // Load media for all messages and resolve relative paths to absolute
      Map<String, List<MediaAttachment>> mediaMap = {};
      if (widget.mediaAttachmentRepo != null && messages.isNotEmpty) {
        final ids = messages.map((m) => m.id).toList();
        final rawMap =
            await widget.mediaAttachmentRepo!.getAttachmentsForMessages(ids);

        // Resolve relative paths to absolute for display
        for (final entry in rawMap.entries) {
          final resolved = <MediaAttachment>[];
          for (final attachment in entry.value) {
            if (attachment.localPath != null &&
                widget.mediaFileManager != null) {
              final absolutePath = await widget.mediaFileManager!
                  .resolveStoredPath(attachment.localPath!);
              resolved.add(attachment.copyWith(localPath: absolutePath));
            } else {
              resolved.add(attachment);
            }
          }
          mediaMap[entry.key] = resolved;
        }

        // Download pending media
        _downloadPendingMedia(mediaMap);
      }

      setState(() {
        _messages = messages;
        _mediaMap = mediaMap;
      });

      await widget.msgRepo.markAsRead(widget.group.id);
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_CONV_FL_LOAD_MESSAGES_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _downloadPendingMedia(
      Map<String, List<MediaAttachment>> mediaMap) async {
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
              final list = _mediaMap[entry.key] ?? [];
              final idx = list.indexWhere((a) => a.id == attachment.id);
              if (idx >= 0) {
                list[idx] = downloaded ??
                    attachment.copyWith(downloadStatus: 'failed');
                _mediaMap[entry.key] = list;
              }
            });
          }
        }
      }
    }
  }

  void _startListening() {
    _messageSubscription =
        widget.groupMessageListener.groupMessageStream.listen(
      (message) {
        if (message.groupId == widget.group.id) {
          _loadMessages();
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

  Future<void> _onSend(String text) async {
    if (_ownPeerId == null) return;

    final hasAttachments = _pendingAttachments.isNotEmpty;
    if (text.isEmpty && !hasAttachments) return;

    // Upload attachments first (if any)
    List<MediaAttachment>? uploadedAttachments;
    if (_pendingAttachments.isNotEmpty) {
      final mediaToUpload = List<_PendingMedia>.from(_pendingAttachments);
      setState(() {
        _pendingAttachments = [];
        _isUploading = true;
      });

      // Get group members for allowedPeers (relay access control)
      final members = await widget.groupRepo.getMembers(widget.group.id);
      final allowedPeers = members.map((m) => m.peerId).toList();

      uploadedAttachments = [];
      for (final pending in mediaToUpload) {
        final mime = _mimeFromPath(pending.file.path);
        final result = await uploadMedia(
          bridge: widget.bridge,
          localFilePath: pending.file.path,
          mime: mime,
          recipientPeerId: widget.group.id,
          mediaFileManager: widget.mediaFileManager,
          width: pending.width,
          height: pending.height,
          durationMs: pending.durationMs,
          allowedPeers: allowedPeers,
        );
        if (result != null) {
          uploadedAttachments.add(result);
        } else {
          // Upload failed — restore attachments and abort
          if (mounted) {
            setState(() {
              _isUploading = false;
              _pendingAttachments = mediaToUpload;
            });
          }
          return;
        }
      }
      if (mounted) {
        setState(() => _isUploading = false);
      }
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
      mediaAttachments: uploadedAttachments,
      mediaAttachmentRepo: widget.mediaAttachmentRepo,
    );

    if (result == SendGroupMessageResult.success && message != null) {
      _loadMessages();
    }
  }

  // -------------------------------------------------------------------------
  // Attachment picker
  // -------------------------------------------------------------------------

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
              title: const Text('Media Library',
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _pickFromGallery();
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.white),
              title: const Text('Take Photo',
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _pickFromCamera();
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam, color: Colors.white),
              title: const Text('Record Video',
                  style: TextStyle(color: Colors.white)),
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
      final picker = ImagePicker();
      final remaining = _maxAttachments - _pendingAttachments.length;
      if (remaining <= 0) return;
      final picked = await picker.pickMultipleMedia();
      if (picked.isEmpty || !mounted) return;
      final selectedFiles = picked.take(remaining).toList();
      final media = <_PendingMedia>[];
      for (final xf in selectedFiles) {
        final result = await _processMediaIfNeeded(xf.path);
        media.add(result);
      }
      if (!mounted) return;
      setState(() {
        _pendingAttachments = [..._pendingAttachments, ...media];
      });
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
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.camera);
      if (picked == null || !mounted) return;
      if (_pendingAttachments.length >= _maxAttachments) return;
      final result = await _processMediaIfNeeded(picked.path);
      if (!mounted) return;
      setState(() {
        _pendingAttachments = [..._pendingAttachments, result];
      });
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
      final picker = ImagePicker();
      final picked = await picker.pickVideo(source: ImageSource.camera);
      if (picked == null || !mounted) return;
      if (_pendingAttachments.length >= _maxAttachments) return;
      final result = await _processMediaIfNeeded(picked.path);
      if (!mounted) return;
      setState(() {
        _pendingAttachments = [..._pendingAttachments, result];
      });
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
      setState(() {
        _isProcessingVideo = true;
        _processingProgress = 0.0;
      });
      final result = await processor.processVideo(
        inputPath: path,
        quality: widget.videoQualityPreference,
        onProgress: (progress) {
          if (mounted) {
            setState(() => _processingProgress = progress / 100.0);
          }
        },
      );
      if (mounted) {
        setState(() => _isProcessingVideo = false);
      }
      return _PendingMedia(
        file: File(result.path),
        width: result.width,
        height: result.height,
        durationMs: result.durationMs,
      );
    }

    final processed = await processor.processImage(
      inputPath: path,
      quality: widget.qualityPreference,
    );
    return _PendingMedia(file: File(processed));
  }

  void _removeAttachment(int index) {
    if (index < 0 || index >= _pendingAttachments.length) return;
    setState(() {
      final updated = List<_PendingMedia>.from(_pendingAttachments);
      updated.removeAt(index);
      _pendingAttachments = updated;
    });
  }

  // -------------------------------------------------------------------------
  // Voice recording
  // -------------------------------------------------------------------------

  Future<void> _onRecordStart() async {
    final recorder = widget.audioRecorderService;
    if (recorder == null || _isRecording) return;

    final hasPermission = await recorder.requestPermission();
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
                'Microphone permission is required to record voice messages.'),
            backgroundColor: Colors.red[700],
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
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
      return;
    }

    _durationSub = recorder.durationStream.listen((d) {
      if (mounted) setState(() => _recordingDuration = d);
    });

    _amplitudeBuffer.reset();
    _waveformSamples = [];
    _amplitudeSub = recorder.amplitudeStream.listen((value) {
      if (mounted) {
        _amplitudeBuffer.push(value);
        _waveformSamples.add(value);
        setState(() => _amplitudeValues = _amplitudeBuffer.values);
      }
    });

    if (mounted) {
      setState(() {
        _isRecording = true;
        _recordingDuration = Duration.zero;
        _amplitudeValues = _amplitudeBuffer.values;
      });
    }
  }

  Future<void> _onRecordStop() async {
    final recorder = widget.audioRecorderService;
    if (recorder == null || !_isRecording) return;

    await _durationSub?.cancel();
    _durationSub = null;
    await _amplitudeSub?.cancel();
    _amplitudeSub = null;
    _amplitudeBuffer.reset();

    final waveform = downsampleWaveform(_waveformSamples, 50);
    _waveformSamples = [];

    final recording = await recorder.stop();

    if (mounted) {
      setState(() {
        _isRecording = false;
        _amplitudeValues = const [];
      });
    }

    if (recording == null || _ownPeerId == null) return;

    // Upload the voice recording
    setState(() => _isUploading = true);

    // Get group members for allowedPeers (relay access control)
    final members = await widget.groupRepo.getMembers(widget.group.id);
    final allowedPeers = members.map((m) => m.peerId).toList();

    final voiceAttachment = await uploadMedia(
      bridge: widget.bridge,
      localFilePath: recording.filePath,
      mime: recording.mime,
      recipientPeerId: widget.group.id,
      mediaFileManager: widget.mediaFileManager,
      durationMs: recording.durationMs,
      waveform: waveform,
      allowedPeers: allowedPeers,
    );

    if (voiceAttachment == null) {
      if (mounted) setState(() => _isUploading = false);
      return;
    }

    if (mounted) setState(() => _isUploading = false);

    await sendGroupMessage(
      bridge: widget.bridge,
      groupRepo: widget.groupRepo,
      msgRepo: widget.msgRepo,
      groupId: widget.group.id,
      text: '',
      senderPeerId: _ownPeerId!,
      senderPublicKey: _senderPublicKey,
      senderPrivateKey: _senderPrivateKey,
      senderUsername: _senderUsername,
      mediaAttachments: [voiceAttachment],
      mediaAttachmentRepo: widget.mediaAttachmentRepo,
    );

    _loadMessages();
  }

  Future<void> _onRecordCancel() async {
    final recorder = widget.audioRecorderService;
    if (recorder == null || !_isRecording) return;

    await _durationSub?.cancel();
    _durationSub = null;
    await _amplitudeSub?.cancel();
    _amplitudeSub = null;
    _amplitudeBuffer.reset();
    _waveformSamples = [];

    await recorder.cancel();

    if (mounted) {
      setState(() {
        _isRecording = false;
        _recordingDuration = Duration.zero;
        _amplitudeValues = const [];
      });
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
      final startIndex =
          allPaths.indexOf(tappedPath).clamp(0, allPaths.length - 1);

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

  bool get _canWrite {
    if (widget.group.type == GroupType.announcement &&
        widget.group.myRole != GroupRole.admin) {
      return false;
    }
    return true;
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

  @override
  void dispose() {
    _messageSubscription?.cancel();
    _durationSub?.cancel();
    _amplitudeSub?.cancel();
    if (_isRecording) {
      widget.audioRecorderService?.cancel();
    }
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GroupConversationScreen(
      group: widget.group,
      messages: _messages,
      ownPeerId: _ownPeerId,
      onSend: _onSend,
      onBack: _onBack,
      onInfo: _onInfo,
      canWrite: _canWrite,
      scrollController: _scrollController,
      mediaMap: _mediaMap,
      pendingAttachments: _pendingAttachments.map((p) => p.file).toList(),
      isUploading: _isUploading,
      isProcessing: _isProcessingVideo,
      processingProgress: _processingProgress,
      onRemoveAttachment: _removeAttachment,
      onAttach: _canWrite ? _onAttach : null,
      onRecordStart:
          _canWrite && widget.audioRecorderService != null ? _onRecordStart : null,
      onRecordStop:
          widget.audioRecorderService != null ? _onRecordStop : null,
      onRecordCancel:
          widget.audioRecorderService != null ? _onRecordCancel : null,
      isRecording: _isRecording,
      recordingDuration: _recordingDuration,
      amplitudeValues: _amplitudeValues,
      onMediaTap: _onMediaTap,
    );
  }
}

