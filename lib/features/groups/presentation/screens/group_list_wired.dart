import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/groups/application/group_invite_listener.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_wired.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_list_screen.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

/// Wired widget connecting GroupListScreen to business logic.
class GroupListWired extends StatefulWidget {
  final GroupRepository groupRepo;
  final GroupMessageRepository msgRepo;
  final GroupMessageListener groupMessageListener;
  final Bridge bridge;
  final IdentityRepository identityRepo;
  final ContactRepository contactRepo;
  final P2PService p2pService;
  final GroupInviteListener? groupInviteListener;

  const GroupListWired({
    super.key,
    required this.groupRepo,
    required this.msgRepo,
    required this.groupMessageListener,
    required this.bridge,
    required this.identityRepo,
    required this.contactRepo,
    required this.p2pService,
    this.groupInviteListener,
  });

  @override
  State<GroupListWired> createState() => _GroupListWiredState();
}

class _GroupListWiredState extends State<GroupListWired> {
  List<GroupModel> _groups = [];
  Map<String, GroupMessage?> _latestMessages = {};
  Map<String, int> _unreadCounts = {};
  StreamSubscription<GroupMessage>? _messageSubscription;
  StreamSubscription<GroupModel>? _inviteSubscription;

  @override
  void initState() {
    super.initState();
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_LIST_FL_SCREEN_INIT',
      details: {},
    );
    _loadGroups();
    _startListening();
  }

  Future<void> _loadGroups() async {
    try {
      final groups = await widget.groupRepo.getActiveGroups();
      final latestMessages = <String, GroupMessage?>{};
      final unreadCounts = <String, int>{};

      for (final group in groups) {
        latestMessages[group.id] =
            await widget.msgRepo.getLatestMessage(group.id);
        unreadCounts[group.id] =
            await widget.msgRepo.getUnreadCount(group.id);
      }

      if (!mounted) return;
      setState(() {
        _groups = groups;
        _latestMessages = latestMessages;
        _unreadCounts = unreadCounts;
      });
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_LIST_FL_LOAD_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  void _startListening() {
    _messageSubscription =
        widget.groupMessageListener.groupMessageStream.listen(
      (_) => _loadGroups(),
      onError: (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_LIST_FL_STREAM_ERROR',
          details: {'error': error.toString()},
        );
      },
    );

    _inviteSubscription = widget.groupInviteListener?.groupJoinedStream.listen(
      (_) => _loadGroups(),
      onError: (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_LIST_FL_INVITE_STREAM_ERROR',
          details: {'error': error.toString()},
        );
      },
    );
  }

  void _onGroupTap(GroupModel group) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GroupConversationWired(
          group: group,
          groupRepo: widget.groupRepo,
          msgRepo: widget.msgRepo,
          groupMessageListener: widget.groupMessageListener,
          bridge: widget.bridge,
          identityRepo: widget.identityRepo,
          contactRepo: widget.contactRepo,
          p2pService: widget.p2pService,
        ),
      ),
    ).then((_) => _loadGroups());
  }

  void _onBack() {
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    _inviteSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GroupListScreen(
      groups: _groups,
      latestMessages: _latestMessages,
      unreadCounts: _unreadCounts,
      onGroupTap: _onGroupTap,
      onBack: _onBack,
    );
  }
}
