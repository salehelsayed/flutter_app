import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_app/core/bridge/js_bridge_client.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
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
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/conversation/presentation/navigation/conversation_route_transition.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_wired.dart';
import 'package:flutter_app/features/conversation/application/mark_conversation_read_use_case.dart';
import 'package:flutter_app/features/feed/application/load_feed_use_case.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/orbit/presentation/navigation/orbit_route_transition.dart';
import 'package:flutter_app/features/orbit/presentation/screens/orbit_wired.dart';
import 'feed_screen.dart';

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
  final ChatMessageListener chatMessageListener;
  final JsBridge bridge;
  final P2PService p2pService;

  const FeedWired({
    super.key,
    required this.repository,
    required this.contactRepository,
    required this.contactRequestRepository,
    required this.contactRequestListener,
    required this.messageRepository,
    required this.chatMessageListener,
    required this.bridge,
    required this.p2pService,
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
  int _totalUnreadCount = 0;
  String? _expandedCardId;
  StreamSubscription<ContactRequestModel>? _requestSubscription;
  StreamSubscription<ConversationMessage>? _chatSubscription;
  StreamSubscription<ContactModel>? _contactUpdateSubscription;

  @override
  void initState() {
    super.initState();
    emitFlowEvent(layer: 'FL', event: 'FEED_FL_SCREEN_INIT', details: {});
    _loadIdentity();
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

      setState(() {
        _identity = identity;
        _username = identity.username;
        _avatarBytes = identity.avatarBlob;
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

  Future<void> _loadFeedFromDatabase() async {
    try {
      final items = await loadFeed(
        contactRepo: widget.contactRepository,
        messageRepo: widget.messageRepository,
      );
      if (!mounted) return;

      setState(() {
        _feedItems.clear();
        _feedItems.addAll(items);
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
    setState(() {
      for (var i = 0; i < _feedItems.length; i++) {
        final item = _feedItems[i];
        if (item is ConnectionFeedItem &&
            item.contactPeerId == contact.peerId) {
          _feedItems[i] = ConnectionFeedItem(
            id: item.id,
            timestamp: item.timestamp,
            contactPeerId: item.contactPeerId,
            contactUsername: contact.username,
            contactAvatarPath: item.contactAvatarPath,
          );
        } else if (item is ThreadFeedItem &&
            item.contactPeerId == contact.peerId) {
          _feedItems[i] = ThreadFeedItem(
            id: item.id,
            timestamp: item.timestamp,
            contactPeerId: item.contactPeerId,
            contactUsername: contact.username,
            messages: item.messages,
            unreadCount: item.unreadCount,
            isUnreadCard: item.isUnreadCard,
          );
        } else if (item is MessageFeedItem &&
            item.contactPeerId == contact.peerId) {
          _feedItems[i] = MessageFeedItem(
            id: item.id,
            timestamp: item.timestamp,
            contactPeerId: item.contactPeerId,
            contactUsername: contact.username,
            messageId: item.messageId,
            messageText: item.messageText,
            messageTime: item.messageTime,
          );
        }
      }
    });
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
        ),
      ),
    ).then((_) => _refreshFeed());
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
            chatMessageListener: widget.chatMessageListener,
            bridge: widget.bridge,
            p2pService: widget.p2pService,
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
    setState(() {
      _expandedCardId = _expandedCardId == cardId ? null : cardId;
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
        onUsernameChanged: _onUsernameChanged,
        p2pService: widget.p2pService,
        onSwitchView: _onSwitchView,
        activeTab: _activeTab,
        onSendMessage: _onSendMessage,
        onReplyToMessage: _onReplyToMessage,
        totalUnreadCount: _totalUnreadCount,
        expandedCardId: _expandedCardId,
        onToggleExpand: _onToggleExpand,
      ),
    );
  }
}
