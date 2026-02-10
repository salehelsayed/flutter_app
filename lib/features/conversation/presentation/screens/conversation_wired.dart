import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/load_conversation_use_case.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'conversation_screen.dart';

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

  const ConversationWired({
    super.key,
    required this.contact,
    required this.identityRepo,
    required this.messageRepo,
    required this.chatMessageListener,
    required this.p2pService,
  });

  @override
  State<ConversationWired> createState() => _ConversationWiredState();
}

class _ConversationWiredState extends State<ConversationWired> {
  IdentityModel? _identity;
  late ContactModel _contact;
  List<ConversationMessage> _messages = [];
  StreamSubscription<ConversationMessage>? _incomingSubscription;
  StreamSubscription<ContactModel>? _contactUpdateSubscription;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _contact = widget.contact;
    emitFlowEvent(layer: 'FL', event: 'CONV_FL_SCREEN_INIT', details: {});
    _loadIdentity();
    _loadMessages();
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

  Future<void> _loadMessages() async {
    try {
      final messages = await loadConversation(
        messageRepo: widget.messageRepo,
        contactPeerId: _contact.peerId,
      );
      if (mounted) {
        setState(() => _messages = messages);
        emitFlowEvent(
          layer: 'FL',
          event: 'CONV_FL_MESSAGES_LOADED',
          details: {'count': messages.length},
        );
        _scrollToBottom();
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONV_FL_LOAD_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  void _startListeningForMessages() {
    _incomingSubscription = widget.chatMessageListener.incomingMessageStream
        .where((msg) => msg.contactPeerId == _contact.peerId)
        .listen(_onIncomingMessage);
  }

  void _onIncomingMessage(ConversationMessage message) {
    if (!mounted) return;
    setState(() {
      _messages = [..._messages, message];
    });
    _scrollToBottom();
  }

  void _startListeningForContactUpdates() {
    _contactUpdateSubscription = widget.chatMessageListener.contactUpdatedStream
        .where((c) => c.peerId == _contact.peerId)
        .listen((updatedContact) {
      if (!mounted) return;
      setState(() => _contact = updatedContact);
    });
  }

  Future<void> _onSend(String text) async {
    final identity = _identity;
    if (identity == null) return;

    emitFlowEvent(
      layer: 'FL',
      event: 'CONV_FL_SEND_PRESSED',
      details: {'textLength': text.length},
    );

    final (result, message) = await sendChatMessage(
      p2pService: widget.p2pService,
      messageRepo: widget.messageRepo,
      targetPeerId: _contact.peerId,
      text: text,
      senderPeerId: identity.peerId,
      senderUsername: identity.username,
    );

    if (!mounted) return;

    if (message != null) {
      setState(() {
        _messages = [..._messages, message];
      });
      _scrollToBottom();
    }

    if (result != SendChatMessageResult.success) {
      final snackText = switch (result) {
        SendChatMessageResult.nodeNotRunning =>
          'Network not connected. Message saved.',
        SendChatMessageResult.peerNotFound =>
          'Contact appears offline. Message saved.',
        SendChatMessageResult.dialFailed =>
          'Could not connect to contact. Message saved.',
        SendChatMessageResult.invalidMessage =>
          'Message cannot be empty.',
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

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
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
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December',
      ];
      return '${months[date.month - 1]} ${date.day}, ${date.year}';
    } catch (_) {
      return '';
    }
  }

  @override
  void dispose() {
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
      ),
    );
  }
}
