import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/application/block_contact_use_case.dart';
import 'package:flutter_app/features/contacts/application/delete_contact_use_case.dart';
import 'package:flutter_app/features/contacts/application/unblock_contact_use_case.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/confirmation_dialog.dart';
import 'package:flutter_app/features/conversation/application/load_conversation_use_case.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/conversation/application/mark_conversation_read_use_case.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
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
      List<MediaAttachment>? mediaAttachments,
      MediaAttachmentRepository? mediaAttachmentRepo,
    });

/// Wired widget that connects ConversationScreen to business logic.
///
/// Loads identity and messages on init, subscribes to incoming message stream,
/// and handles sending messages via use cases.
class ConversationWired extends StatefulWidget {
  final ContactModel contact;
  final IdentityRepository identityRepo;
  final MessageRepository messageRepo;
  final ChatMessageListener chatMessageListener;
  final P2PService p2pService;
  final Bridge? bridge;
  final SendChatMessageFn sendChatMessageFn;
  final List<ConversationMessage>? initialMessages;
  final ContactRepository? contactRepo;
  final MediaAttachmentRepository? mediaAttachmentRepo;
  final MediaFileManager? mediaFileManager;
  final List<File>? initialAttachments;

  const ConversationWired({
    super.key,
    required this.contact,
    required this.identityRepo,
    required this.messageRepo,
    required this.chatMessageListener,
    required this.p2pService,
    this.bridge,
    this.sendChatMessageFn = sendChatMessage,
    this.initialMessages,
    this.contactRepo,
    this.mediaAttachmentRepo,
    this.mediaFileManager,
    this.initialAttachments,
  });

  @override
  State<ConversationWired> createState() => _ConversationWiredState();
}

class _ConversationWiredState extends State<ConversationWired> {
  static const _uuid = Uuid();
  static const _pageSize = 50;

  IdentityModel? _identity;
  late ContactModel _contact;
  List<ConversationMessage> _messages = [];
  StreamSubscription<ConversationMessage>? _incomingSubscription;
  StreamSubscription<ContactModel>? _contactUpdateSubscription;
  final _scrollController = ScrollController();

  bool _hasMoreOlderMessages = true;
  bool _isLoadingMore = false;
  bool _initialLoadDone = false;

  List<File> _pendingAttachments = [];
  bool _isUploading = false;
  static const _maxAttachments = 10;

  @override
  void initState() {
    super.initState();
    _contact = widget.contact;
    if (widget.initialAttachments != null && widget.initialAttachments!.isNotEmpty) {
      _pendingAttachments = List<File>.from(widget.initialAttachments!);
    }
    emitFlowEvent(layer: 'FL', event: 'CONV_FL_SCREEN_INIT', details: {});
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
    _startListeningForContactUpdates();
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
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _initialLoadDone = true);
        });
      }
    } catch (e) {
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
            emitFlowEvent(layer: 'FL', event: 'CONV_CHAT_STREAM_ERROR', details: {'error': error.toString()});
          },
          onDone: () {
            emitFlowEvent(layer: 'FL', event: 'CONV_CHAT_STREAM_DONE', details: {});
          },
        );
  }

  void _onIncomingMessage(ConversationMessage message) {
    if (!mounted) return;
    setState(() {
      _upsertMessageById(message);
    });
    _scrollToBottom();
    _markAsRead();
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
            emitFlowEvent(layer: 'FL', event: 'CONV_CONTACT_UPDATE_STREAM_ERROR', details: {'error': error.toString()});
          },
          onDone: () {
            emitFlowEvent(layer: 'FL', event: 'CONV_CONTACT_UPDATE_STREAM_DONE', details: {});
          },
        );
  }

  Future<void> _onSend(String text) async {
    final identity = _identity;
    if (identity == null) return;

    final hasAttachments = _pendingAttachments.isNotEmpty;
    if (text.isEmpty && !hasAttachments) return;

    emitFlowEvent(
      layer: 'FL',
      event: 'CONV_FL_SEND_PRESSED',
      details: {'textLength': text.length, 'attachments': _pendingAttachments.length},
    );

    // Capture and clear pending attachments
    final filesToUpload = List<File>.from(_pendingAttachments);
    List<MediaAttachment>? optimisticMedia;

    if (filesToUpload.isNotEmpty) {
      final now = DateTime.now().toUtc().toIso8601String();
      optimisticMedia = filesToUpload.map((f) {
        final mime = _mimeFromPath(f.path);
        return MediaAttachment(
          id: _uuid.v4(),
          messageId: '',
          mime: mime,
          size: 0,
          mediaType: MediaAttachment.mediaTypeFromMime(mime),
          localPath: f.path,
          downloadStatus: 'done',
          createdAt: now,
        );
      }).toList();
    }

    setState(() {
      _pendingAttachments = [];
      if (filesToUpload.isNotEmpty) _isUploading = true;
    });

    final now = DateTime.now().toUtc().toIso8601String();
    final optimisticMessage = ConversationMessage(
      id: _uuid.v4(),
      contactPeerId: _contact.peerId,
      senderPeerId: identity.peerId,
      text: text,
      timestamp: now,
      status: 'sending',
      isIncoming: false,
      createdAt: now,
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
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONV_FL_OPTIMISTIC_SAVE_ERROR',
        details: {'error': e.toString()},
      );
    }

    // Upload attachments if any
    List<MediaAttachment>? uploadedAttachments;
    if (filesToUpload.isNotEmpty && widget.bridge != null) {
      uploadedAttachments = [];
      for (final file in filesToUpload) {
        final mime = _mimeFromPath(file.path);
        final result = await uploadMedia(
          bridge: widget.bridge!,
          localFilePath: file.path,
          mime: mime,
          recipientPeerId: _contact.peerId,
          mediaFileManager: widget.mediaFileManager,
        );

        if (result == null) {
          // Upload failed — restore attachments, mark message failed
          if (mounted) {
            setState(() {
              _isUploading = false;
              _pendingAttachments = filesToUpload;
            });
            _updateLocalMessageStatus(optimisticMessage.id, 'failed');
            await _persistMessageStatus(optimisticMessage.id, 'failed');
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Failed to upload media. Try again.'),
                backgroundColor: Colors.red[700],
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          return;
        }
        uploadedAttachments.add(result);
      }
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }

    final (result, message) = await widget.sendChatMessageFn(
      p2pService: widget.p2pService,
      messageRepo: widget.messageRepo,
      targetPeerId: _contact.peerId,
      text: text,
      senderPeerId: identity.peerId,
      senderUsername: identity.username,
      messageId: optimisticMessage.id,
      timestamp: optimisticMessage.timestamp,
      bridge: widget.bridge,
      recipientMlKemPublicKey: _contact.mlKemPublicKey,
      mediaAttachments: uploadedAttachments,
      mediaAttachmentRepo: widget.mediaAttachmentRepo,
    );

    if (!mounted) return;

    if (message != null) {
      // Resolve relative paths from uploaded attachments to absolute for display
      List<MediaAttachment>? displayMedia;
      if (uploadedAttachments != null && widget.mediaFileManager != null) {
        displayMedia = [];
        for (final a in uploadedAttachments) {
          if (a.localPath != null) {
            final absPath =
                await widget.mediaFileManager!.resolveStoredPath(a.localPath!);
            displayMedia.add(a.copyWith(localPath: absPath));
          } else {
            displayMedia.add(a);
          }
        }
      }
      final persistedMedia = displayMedia ?? optimisticMedia;
      final messageWithMedia = persistedMedia != null
          ? message.copyWith(media: persistedMedia)
          : message;
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
        _ => 'Failed to send message. Message saved.',
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
                'Photo Library',
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
                'Camera',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _pickFromCamera();
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

      final picked = await picker.pickMultiImage(imageQuality: 85);
      if (picked.isEmpty || !mounted) return;

      final files = picked
          .take(remaining)
          .map((xf) => File(xf.path))
          .toList();
      setState(() {
        _pendingAttachments = [..._pendingAttachments, ...files];
      });
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
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
      if (picked == null || !mounted) return;
      if (_pendingAttachments.length >= _maxAttachments) return;

      setState(() {
        _pendingAttachments = [..._pendingAttachments, File(picked.path)];
      });
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONV_FL_PICK_CAMERA_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  void _removeAttachment(int index) {
    if (index < 0 || index >= _pendingAttachments.length) return;
    setState(() {
      final updated = List<File>.from(_pendingAttachments);
      updated.removeAt(index);
      _pendingAttachments = updated;
    });
  }

  void _upsertMessageById(ConversationMessage message) {
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
        side: const BorderSide(
          color: Color.fromRGBO(255, 255, 255, 0.14),
        ),
      ),
      items: [
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
              Icon(
                Icons.delete_outline,
                size: 18,
                color: Color(0xFFEF4444),
              ),
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
      if (value == 'block') {
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
      title: 'Block ${_contact.username}?',
      description:
          'They won\'t be able to send you messages. You can unblock them later.',
      confirmLabel: 'Block',
    );
    if (!confirmed || !mounted) return;

    try {
      await blockContact(
        contactRepo: contactRepo,
        peerId: _contact.peerId,
      );
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
      await unblockContact(
        contactRepo: contactRepo,
        peerId: _contact.peerId,
      );
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
      title: 'Delete chat?',
      description:
          'This will permanently remove ${_contact.username} and all messages. This cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (!confirmed || !mounted) return;

    try {
      await deleteContactAndMessages(
        contactRepo: contactRepo,
        messageRepo: widget.messageRepo,
        peerId: _contact.peerId,
      );
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
      const months = [
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December',
      ];
      return '${months[date.month - 1]} ${date.day}, ${date.year}';
    } catch (_) {
      return '';
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _incomingSubscription?.cancel();
    _contactUpdateSubscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ConversationScreen(
        contactPeerId: _contact.peerId,
        contactUsername: _contact.username,
        connectionDate: _formatConnectionDate(),
        ownPeerId: _identity?.peerId,
        messages: _messages,
        onSend: _onSend,
        onBack: () => Navigator.of(context).pop(),
        scrollController: _scrollController,
        isBlocked: _contact.isBlocked,
        onUnblock: _onUnblock,
        onOverflow: widget.contactRepo != null ? _onOverflow : null,
        isLoadingMore: _isLoadingMore,
        hasMoreOlderMessages: _hasMoreOlderMessages,
        initialLoadDone: _initialLoadDone,
        onAttach: _onAttach,
        pendingAttachments: _pendingAttachments,
        isUploading: _isUploading,
        onRemoveAttachment: _removeAttachment,
      ),
    );
  }
}
