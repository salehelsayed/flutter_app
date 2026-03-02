import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_screen.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_info_wired.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

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
  });

  @override
  State<GroupConversationWired> createState() => _GroupConversationWiredState();
}

class _GroupConversationWiredState extends State<GroupConversationWired> {
  List<GroupMessage> _messages = [];
  String? _ownPeerId;
  String _senderUsername = '';
  String _senderPublicKey = '';
  String _senderPrivateKey = '';
  StreamSubscription<GroupMessage>? _messageSubscription;
  final ScrollController _scrollController = ScrollController();

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
      setState(() => _messages = messages);

      // Mark messages as read
      await widget.msgRepo.markAsRead(widget.group.id);
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_CONV_FL_LOAD_MESSAGES_ERROR',
        details: {'error': e.toString()},
      );
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
    );

    if (result == SendGroupMessageResult.success && message != null) {
      _loadMessages();
    }
  }

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

  @override
  void dispose() {
    _messageSubscription?.cancel();
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
    );
  }
}
