import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/settings/application/image_quality_preference_use_cases.dart';
import 'package:flutter_app/features/settings/domain/models/image_quality_preference.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contact_request/application/accept_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contact_request/application/decline_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/contact_request/domain/repositories/contact_request_repository.dart';
import 'package:flutter_app/features/contact_request/presentation/widgets/contact_request_dialog.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/load_conversation_use_case.dart';
import 'package:flutter_app/features/conversation/application/mark_conversation_read_use_case.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/conversation/presentation/navigation/conversation_route_transition.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_wired.dart';
import 'package:flutter_app/features/feed/application/load_feed_use_case.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/domain/models/session_reply.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/orbit/presentation/navigation/orbit_route_transition.dart';
import 'package:flutter_app/features/orbit/presentation/screens/orbit_wired.dart';
import 'package:flutter_app/features/settings/presentation/navigation/settings_route_transition.dart';
import 'package:flutter_app/features/settings/presentation/screens/settings_wired.dart';
import 'feed_screen.dart';

enum _MediaSource { gallery, camera, videoCamera }

/// Wired widget that connects FeedScreen to business logic.
///
/// Follows the same "Wired" pattern as FirstTimeExperienceWired.
/// Loads identity, builds feed items from the initial contact,
/// and listens for new incoming contact requests.
class FeedWired extends StatefulWidget {
  final IdentityRepository repository;
  final ContactRepository contactRepository;
  final ContactRequestRepository contactRequestRepository;
  final ContactRequestListener contactRequestListener;
  final MessageRepository messageRepository;
  final MediaAttachmentRepository mediaAttachmentRepository;
  final ChatMessageListener chatMessageListener;
  final Bridge bridge;
  final P2PService p2pService;
  final MediaFileManager mediaFileManager;
  final SecureKeyStore secureKeyStore;
  final ImageProcessor imageProcessor;

  const FeedWired({
    super.key,
    required this.repository,
    required this.contactRepository,
    required this.contactRequestRepository,
    required this.contactRequestListener,
    required this.messageRepository,
    required this.mediaAttachmentRepository,
    required this.chatMessageListener,
    required this.bridge,
    required this.p2pService,
    required this.mediaFileManager,
    required this.secureKeyStore,
    required this.imageProcessor,
  });

  @override
  State<FeedWired> createState() => _FeedWiredState();
}

class _FeedWiredState extends State<FeedWired> {
  String _username = 'Username';
  Uint8List? _avatarBytes;
  String? _peerId;
  IdentityModel? _identity;
  String _activeTab = 'feed';
  final List<FeedItem> _feedItems = [];
  bool _feedLoaded = false;
  int _totalUnreadCount = 0;
  String? _expandedCardId;
  final Map<String, String> _draftTexts = {};
  final Map<String, String> _activeQuoteMessageIds = {};
  final SessionReplyTracker _sessionReplies = SessionReplyTracker();
  String? _activeFocusPeerId;
  StreamSubscription<ContactRequestModel>? _requestSubscription;
  StreamSubscription<ConversationMessage>? _chatSubscription;
  StreamSubscription<ContactModel>? _contactUpdateSubscription;
  ImageQualityPreference _qualityPreference = ImageQualityPreference.compressed;
  ImageQualityPreference _videoQualityPreference = ImageQualityPreference.compressed;

  @override
  void initState() {
    super.initState();
    emitFlowEvent(layer: 'FL', event: 'FEED_FL_SCREEN_INIT', details: {});
    _loadIdentity();
    _loadQualityPreference();
    _loadVideoQualityPreference();
    _loadFeedFromDatabase();
    _loadTotalUnreadCount();
    _startListeningForContactRequests();
    _startListeningForChatMessages();
    _startListeningForContactUpdates();
  }

  void _loadIdentity() async {
    try {
      final identity = await widget.repository.loadIdentity();
      if (identity == null || !mounted) return;

      // Load file-based avatar if avatarVersion is set
      Uint8List? avatarBytes = identity.avatarBlob;
      if (identity.avatarVersion != null) {
        try {
          final appDir = await getApplicationDocumentsDirectory();
          final avatarFile = File(
            p.join(appDir.path, 'media', 'avatars', '${identity.peerId}.jpg'),
          );
          if (avatarFile.existsSync()) {
            avatarBytes = await avatarFile.readAsBytes();
          }
        } catch (_) {}
      }

      if (!mounted) return;

      setState(() {
        _identity = identity;
        _username = identity.username;
        _avatarBytes = avatarBytes;
        _peerId = identity.peerId;
      });
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'FEED_FL_LOAD_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _loadQualityPreference() async {
    final pref = await loadImageQualityPreference(
      secureKeyStore: widget.secureKeyStore,
    );
    if (mounted) {
      setState(() => _qualityPreference = pref);
    }
  }

  Future<void> _loadVideoQualityPreference() async {
    final pref = await loadVideoQualityPreference(
      secureKeyStore: widget.secureKeyStore,
    );
    if (mounted) {
      setState(() => _videoQualityPreference = pref);
    }
  }

  Future<void> _loadFeedFromDatabase() async {
    try {
      final items = await loadFeed(
        contactRepo: widget.contactRepository,
        messageRepo: widget.messageRepository,
        mediaAttachmentRepo: widget.mediaAttachmentRepository,
        mediaFileManager: widget.mediaFileManager,
      );
      if (!mounted) return;

      setState(() {
        _feedItems.clear();
        _feedItems.addAll(items);
        _feedLoaded = true;
      });
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'FEED_FL_DB_LOAD_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _loadTotalUnreadCount() async {
    try {
      final count = await widget.messageRepository.getTotalUnreadCountExcludingArchived();
      if (!mounted) return;
      setState(() => _totalUnreadCount = count);
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'FEED_FL_UNREAD_COUNT_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _refreshFeed() async {
    await _loadTotalUnreadCount();
    await _loadFeedFromDatabase();
  }

  void _startListeningForContactRequests() {
    _requestSubscription = widget.contactRequestListener.requestStream.listen(
      _onContactRequest,
      onError: (error) {
        emitFlowEvent(layer: 'FL', event: 'FEED_REQUEST_STREAM_ERROR', details: {'error': error.toString()});
      },
      onDone: () {
        emitFlowEvent(layer: 'FL', event: 'FEED_REQUEST_STREAM_DONE', details: {});
      },
    );
  }

  void _onContactRequest(ContactRequestModel request) {
    emitFlowEvent(
      layer: 'FL',
      event: 'FEED_FL_CONTACT_REQUEST_RECEIVED',
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

    final result = await acceptContactRequest(
      requestRepo: widget.contactRequestRepository,
      contactRepo: widget.contactRepository,
      peerId: request.peerId,
    );

    if (!mounted) return;

    if (result == AcceptContactRequestResult.success) {
      final contact = request.toContactModel();
      final alreadyExists = _feedItems.any(
        (item) =>
            item is ConnectionFeedItem &&
            item.contactPeerId == contact.peerId,
      );
      if (!alreadyExists) {
        final item = ConnectionFeedItem.fromContact(contact);
        setState(() {
          _feedItems.insert(0, item);
        });
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Failed to add contact. Please try again.'),
          backgroundColor: Colors.red[700],
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _declineRequest(
    BuildContext ctx,
    ContactRequestModel request,
  ) async {
    Navigator.pop(ctx);

    await declineContactRequest(
      requestRepo: widget.contactRequestRepository,
      peerId: request.peerId,
    );
  }

  void _startListeningForChatMessages() {
    _chatSubscription =
        widget.chatMessageListener.incomingMessageStream.listen(
      _onIncomingChatMessage,
      onError: (error) {
        emitFlowEvent(layer: 'FL', event: 'FEED_CHAT_STREAM_ERROR', details: {'error': error.toString()});
      },
      onDone: () {
        emitFlowEvent(layer: 'FL', event: 'FEED_CHAT_STREAM_DONE', details: {});
      },
    );
  }

  void _onIncomingChatMessage(ConversationMessage message) {
    if (!mounted) return;
    _refreshFeed();
  }

  void _startListeningForContactUpdates() {
    _contactUpdateSubscription =
        widget.chatMessageListener.contactUpdatedStream.listen(
      _onContactUpdated,
      onError: (error) {
        emitFlowEvent(layer: 'FL', event: 'FEED_CONTACT_UPDATE_STREAM_ERROR', details: {'error': error.toString()});
      },
      onDone: () {
        emitFlowEvent(layer: 'FL', event: 'FEED_CONTACT_UPDATE_STREAM_DONE', details: {});
      },
    );
  }

  void _onContactUpdated(ContactModel contact) {
    if (!mounted) return;
    _refreshFeed();
  }

  void _onSendMessage(ConnectionFeedItem item) async {
    final contact = await widget.contactRepository.getContact(item.contactPeerId);
    if (contact == null || !mounted) return;

    await markConversationRead(
      messageRepo: widget.messageRepository,
      contactPeerId: item.contactPeerId,
    );

    if (!mounted) return;

    Navigator.of(context).push(
      buildConversationSlideUpRoute(
        builder: (_) => ConversationWired(
          contact: contact,
          identityRepo: widget.repository,
          messageRepo: widget.messageRepository,
          chatMessageListener: widget.chatMessageListener,
          p2pService: widget.p2pService,
          bridge: widget.bridge,
          contactRepo: widget.contactRepository,
          mediaAttachmentRepo: widget.mediaAttachmentRepository,
          mediaFileManager: widget.mediaFileManager,
          imageProcessor: widget.imageProcessor,
          qualityPreference: _qualityPreference,
          videoQualityPreference: _videoQualityPreference,
        ),
      ),
    ).then((_) => _refreshFeed());
  }

  void _onReplyToMessage(String contactPeerId) async {
    final results = await Future.wait([
      widget.contactRepository.getContact(contactPeerId),
      loadConversation(
        messageRepo: widget.messageRepository,
        contactPeerId: contactPeerId,
        mediaAttachmentRepo: widget.mediaAttachmentRepository,
        mediaFileManager: widget.mediaFileManager,
      ),
    ]);

    final contact = results[0] as ContactModel?;
    final messages = results[1] as List<ConversationMessage>;
    if (contact == null || !mounted) return;

    Navigator.of(context).push(
      buildConversationSlideUpRoute(
        builder: (_) => ConversationWired(
          contact: contact,
          identityRepo: widget.repository,
          messageRepo: widget.messageRepository,
          chatMessageListener: widget.chatMessageListener,
          p2pService: widget.p2pService,
          bridge: widget.bridge,
          initialMessages: messages,
          contactRepo: widget.contactRepository,
          mediaAttachmentRepo: widget.mediaAttachmentRepository,
          mediaFileManager: widget.mediaFileManager,
          imageProcessor: widget.imageProcessor,
          qualityPreference: _qualityPreference,
          videoQualityPreference: _videoQualityPreference,
        ),
      ),
    ).then((_) => _refreshFeed());
  }

  Future<void> _onInlineSend(String contactPeerId, String text) async {
    final identity = _identity;
    if (identity == null) return;

    try {
      final contact =
          await widget.contactRepository.getContact(contactPeerId);
      if (contact == null || !mounted) return;

      final quotedMsgId = _activeQuoteMessageIds[contactPeerId];
      final (result, _) = await sendChatMessage(
        p2pService: widget.p2pService,
        messageRepo: widget.messageRepository,
        targetPeerId: contactPeerId,
        text: text,
        senderPeerId: identity.peerId,
        senderUsername: identity.username,
        bridge: widget.bridge,
        recipientMlKemPublicKey: contact.mlKemPublicKey,
        quotedMessageId: quotedMsgId,
      );

      if (!mounted) return;

      if (result == SendChatMessageResult.success) {
        _draftTexts.remove(contactPeerId);
        _activeQuoteMessageIds.remove(contactPeerId);
        _sessionReplies.track(
          contactPeerId,
          SessionReply.justNow(text),
        );
        // Mark as read on successful inline reply
        await markConversationRead(
          messageRepo: widget.messageRepository,
          contactPeerId: contactPeerId,
        );
        await _refreshFeed();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Message failed to send. Try again.'),
            backgroundColor: Colors.red[700],
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'FEED_FL_INLINE_SEND_ERROR',
        details: {'error': e.toString()},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Message failed to send. Try again.'),
          backgroundColor: Colors.red[700],
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _onViewFullConversation(String contactPeerId) {
    _onReplyToMessage(contactPeerId);
  }

  void _onAttach(String contactPeerId) {
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
                _pickAndOpenConversation(contactPeerId, source: _MediaSource.gallery);
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
                _pickAndOpenConversation(contactPeerId, source: _MediaSource.camera);
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
                _pickAndOpenConversation(contactPeerId, source: _MediaSource.videoCamera);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndOpenConversation(
    String contactPeerId, {
    required _MediaSource source,
  }) async {
    try {
      final picker = ImagePicker();
      List<File> files;

      switch (source) {
        case _MediaSource.camera:
          final picked = await picker.pickImage(
            source: ImageSource.camera,
          );
          if (picked == null || !mounted) return;
          final path = await _processMediaPath(picked.path);
          files = [File(path)];
        case _MediaSource.videoCamera:
          final picked = await picker.pickVideo(
            source: ImageSource.camera,
          );
          if (picked == null || !mounted) return;
          _showProcessingSnackBar();
          final path = await _processMediaPath(picked.path);
          if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
          files = [File(path)];
        case _MediaSource.gallery:
          final picked = await picker.pickMultipleMedia();
          if (picked.isEmpty || !mounted) return;
          final hasVideo = picked.any(
            (xf) => widget.imageProcessor.isProcessableVideo(xf.path),
          );
          if (hasVideo) _showProcessingSnackBar();
          final processedFiles = <File>[];
          for (final xf in picked) {
            final path = await _processMediaPath(xf.path);
            processedFiles.add(File(path));
          }
          if (hasVideo && mounted) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          }
          files = processedFiles;
      }

      final contact =
          await widget.contactRepository.getContact(contactPeerId);
      if (contact == null || !mounted) return;

      await markConversationRead(
        messageRepo: widget.messageRepository,
        contactPeerId: contactPeerId,
      );

      if (!mounted) return;

      Navigator.of(context).push(
        buildConversationSlideUpRoute(
          builder: (_) => ConversationWired(
            contact: contact,
            identityRepo: widget.repository,
            messageRepo: widget.messageRepository,
            chatMessageListener: widget.chatMessageListener,
            p2pService: widget.p2pService,
            bridge: widget.bridge,
            contactRepo: widget.contactRepository,
            mediaAttachmentRepo: widget.mediaAttachmentRepository,
            mediaFileManager: widget.mediaFileManager,
            initialAttachments: files,
            imageProcessor: widget.imageProcessor,
            qualityPreference: _qualityPreference,
            videoQualityPreference: _videoQualityPreference,
          ),
        ),
      ).then((_) => _refreshFeed());
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'FEED_FL_PICK_ATTACH_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  void _showProcessingSnackBar() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Processing video\u2026'),
        duration: Duration(minutes: 5),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Processes a media file (image or video) and returns the processed path.
  Future<String> _processMediaPath(String path) async {
    final processor = widget.imageProcessor;
    if (processor.isProcessableVideo(path)) {
      final result = await processor.processVideo(
        inputPath: path,
        quality: _videoQualityPreference,
      );
      return result.path;
    }
    return processor.processImage(
      inputPath: path,
      quality: _qualityPreference,
    );
  }

  void _onAvatarTap() {
    Navigator.of(context).push(
      buildSettingsSlideUpRoute(
        builder: (_) => SettingsWired(
          identityRepo: widget.repository,
          bridge: widget.bridge,
          contactRepo: widget.contactRepository,
          p2pService: widget.p2pService,
          secureKeyStore: widget.secureKeyStore,
          imageProcessor: widget.imageProcessor,
        ),
      ),
    ).then((_) {
      _loadIdentity();
      _loadQualityPreference();
      _loadVideoQualityPreference();
    });
  }

  void _onSwitchView(String tab) {
    if (tab == 'orbit') {
      Navigator.of(context).push(
        buildOrbitSlideUpRoute(
          builder: (_) => OrbitWired(
            identityRepo: widget.repository,
            contactRepo: widget.contactRepository,
            contactRequestRepo: widget.contactRequestRepository,
            contactRequestListener: widget.contactRequestListener,
            messageRepo: widget.messageRepository,
            mediaAttachmentRepo: widget.mediaAttachmentRepository,
            chatMessageListener: widget.chatMessageListener,
            bridge: widget.bridge,
            p2pService: widget.p2pService,
            mediaFileManager: widget.mediaFileManager,
            secureKeyStore: widget.secureKeyStore,
            imageProcessor: widget.imageProcessor,
          ),
        ),
      ).then((_) => _refreshFeed());
      return;
    }
    setState(() {
      _activeTab = tab;
    });
  }

  Future<void> _onUsernameChanged(String newUsername) async {
    final identity = _identity;
    if (identity == null) return;

    final updatedIdentity = IdentityModel(
      peerId: identity.peerId,
      publicKey: identity.publicKey,
      privateKey: identity.privateKey,
      mnemonic12: identity.mnemonic12,
      mlKemPublicKey: identity.mlKemPublicKey,
      mlKemSecretKey: identity.mlKemSecretKey,
      username: newUsername,
      avatarBlob: identity.avatarBlob,
      avatarVersion: identity.avatarVersion,
      createdAt: identity.createdAt,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    );

    try {
      await widget.repository.saveIdentity(updatedIdentity);
      if (!mounted) return;

      setState(() {
        _identity = updatedIdentity;
        _username = newUsername;
      });

      emitFlowEvent(
        layer: 'FL',
        event: 'FEED_FL_USERNAME_UPDATED',
        details: {'username': newUsername},
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'FEED_FL_USERNAME_ERROR',
        details: {'error': e.toString()},
      );
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Failed to update username. Please try again.'),
          backgroundColor: Colors.red[700],
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _onToggleExpand(String cardId) {
    // Mark as read when expanding an unread/active card
    final item = _feedItems.whereType<ThreadFeedItem>().where(
      (t) => t.id == cardId,
    ).firstOrNull;

    if (item != null &&
        _expandedCardId != cardId &&
        (item.conversationState == ConversationState.unread ||
            item.conversationState == ConversationState.active)) {
      markConversationRead(
        messageRepo: widget.messageRepository,
        contactPeerId: item.contactPeerId,
      ).then((_) {
        if (mounted) _refreshFeed();
      });
    }

    // Clear quote when collapsing
    if (_expandedCardId == cardId) {
      final collapsingItem = item;
      if (collapsingItem != null) {
        _activeQuoteMessageIds.remove(collapsingItem.contactPeerId);
      }
    }

    setState(() {
      _expandedCardId = _expandedCardId == cardId ? null : cardId;
    });
  }

  void _onDraftChanged(String contactPeerId, String text) {
    if (text.isEmpty) {
      _draftTexts.remove(contactPeerId);
    } else {
      _draftTexts[contactPeerId] = text;
    }
  }

  void _onInputFocusChanged(String contactPeerId, bool hasFocus) {
    setState(() {
      _activeFocusPeerId = hasFocus ? contactPeerId : null;
    });
  }

  void _onQuoteReply(String contactPeerId, String messageId) {
    setState(() {
      _activeQuoteMessageIds[contactPeerId] = messageId;
    });
  }

  void _onClearQuote(String contactPeerId) {
    setState(() {
      _activeQuoteMessageIds.remove(contactPeerId);
    });
  }

  @override
  void dispose() {
    _requestSubscription?.cancel();
    _chatSubscription?.cancel();
    _contactUpdateSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FeedScreen(
        username: _username,
        userAvatarBytes: _avatarBytes,
        userPeerId: _peerId,
        feedItems: _feedItems,
        feedLoaded: _feedLoaded,
        onUsernameChanged: _onUsernameChanged,
        p2pService: widget.p2pService,
        onSwitchView: _onSwitchView,
        activeTab: _activeTab,
        onSendMessage: _onSendMessage,
        onReplyToMessage: _onReplyToMessage,
        totalUnreadCount: _totalUnreadCount,
        expandedCardId: _expandedCardId,
        onToggleExpand: _onToggleExpand,
        onInlineSend: _onInlineSend,
        onViewFullConversation: _onViewFullConversation,
        draftTexts: _draftTexts,
        activeFocusPeerId: _activeFocusPeerId,
        onDraftChanged: _onDraftChanged,
        onInputFocusChanged: _onInputFocusChanged,
        activeQuoteMessageIds: _activeQuoteMessageIds,
        onQuoteReply: _onQuoteReply,
        onClearQuote: _onClearQuote,
        onAttach: _onAttach,
        onAvatarTap: _onAvatarTap,
        sessionReplies: _sessionReplies,
      ),
    );
  }
}
