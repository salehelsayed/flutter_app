import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/groups/application/leave_group_use_case.dart';
import 'package:flutter_app/features/groups/application/remove_group_member_use_case.dart';
import 'package:flutter_app/features/groups/application/rotate_and_distribute_group_key_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/groups/presentation/screens/contact_picker_wired.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_info_screen.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

/// Wired widget connecting GroupInfoScreen to business logic.
class GroupInfoWired extends StatefulWidget {
  final GroupModel group;
  final GroupRepository groupRepo;
  final ContactRepository contactRepo;
  final Bridge bridge;
  final IdentityRepository identityRepo;
  final P2PService p2pService;

  const GroupInfoWired({
    super.key,
    required this.group,
    required this.groupRepo,
    required this.contactRepo,
    required this.bridge,
    required this.identityRepo,
    required this.p2pService,
  });

  @override
  State<GroupInfoWired> createState() => _GroupInfoWiredState();
}

class _GroupInfoWiredState extends State<GroupInfoWired> {
  List<GroupMember> _members = [];
  String? _ownPeerId;

  @override
  void initState() {
    super.initState();
    _loadMembers();
    _loadIdentity();
  }

  Future<void> _loadIdentity() async {
    final identity = await widget.identityRepo.loadIdentity();
    if (identity != null && mounted) {
      setState(() => _ownPeerId = identity.peerId);
    }
  }

  Future<void> _loadMembers() async {
    try {
      final members = await widget.groupRepo.getMembers(widget.group.id);
      if (!mounted) return;
      setState(() => _members = members);
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_INFO_FL_LOAD_MEMBERS_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _onLeave() async {
    try {
      await leaveGroup(
        bridge: widget.bridge,
        groupRepo: widget.groupRepo,
        groupId: widget.group.id,
      );

      if (!mounted) return;
      // Pop back to group list (pop info screen + conversation screen)
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_INFO_FL_LEAVE_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _onRemoveMember(GroupMember member) async {
    try {
      // 1. Remove from DB + update admin's Go config
      await removeGroupMember(
        bridge: widget.bridge,
        groupRepo: widget.groupRepo,
        groupId: widget.group.id,
        memberPeerId: member.peerId,
      );

      // 2. Broadcast member_removed system message to remaining members
      final identity = await widget.identityRepo.loadIdentity();
      if (identity != null) {
        final group = await widget.groupRepo.getGroup(widget.group.id);
        final allMembers = await widget.groupRepo.getMembers(widget.group.id);

        if (group != null) {
          final groupConfig = {
            'name': group.name,
            'groupType': group.type.toValue(),
            if (group.description != null) 'description': group.description,
            'members': allMembers
                .map(
                  (m) => {
                    'peerId': m.peerId,
                    'username': m.username,
                    'role': m.role.toValue(),
                    'publicKey': m.publicKey,
                    if (m.mlKemPublicKey != null)
                      'mlKemPublicKey': m.mlKemPublicKey,
                  },
                )
                .toList(),
            'createdBy': group.createdBy,
            'createdAt': group.createdAt.toUtc().toIso8601String(),
          };

          final sysMessage = jsonEncode({
            '__sys': 'member_removed',
            'member': {'peerId': member.peerId, 'username': member.username},
            'groupConfig': groupConfig,
          });
          final removalInboxPayload = jsonEncode({
            'groupId': widget.group.id,
            'senderId': identity.peerId,
            'senderUsername': identity.username ?? '',
            'keyEpoch': 0,
            'text': sysMessage,
            'timestamp': DateTime.now().toUtc().toIso8601String(),
          });

          await callGroupPublish(
            widget.bridge,
            groupId: widget.group.id,
            text: sysMessage,
            senderPeerId: identity.peerId,
            senderPublicKey: identity.publicKey,
            senderPrivateKey: identity.privateKey,
            senderUsername: identity.username ?? '',
          );
          await callGroupInboxStore(
            widget.bridge,
            widget.group.id,
            removalInboxPayload,
            recipientPeerIds: [member.peerId],
          );

          emitFlowEvent(
            layer: 'FL',
            event: 'GROUP_INFO_FL_REMOVE_BROADCAST_SENT',
            details: {
              'groupId': widget.group.id.length > 8
                  ? widget.group.id.substring(0, 8)
                  : widget.group.id,
              'removedPeerId': member.peerId.length > 10
                  ? member.peerId.substring(0, 10)
                  : member.peerId,
            },
          );

          // 3. Rotate group key and distribute to remaining members
          await rotateAndDistributeGroupKey(
            bridge: widget.bridge,
            groupRepo: widget.groupRepo,
            groupId: widget.group.id,
            selfPeerId: identity.peerId,
            senderPublicKey: identity.publicKey,
            senderPrivateKey: identity.privateKey,
            senderUsername: identity.username ?? '',
            sendP2PMessage: (peerId, message) async {
              await widget.p2pService.sendMessage(peerId, message);
              return true;
            },
          );
        }
      }

      _loadMembers();
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_INFO_FL_REMOVE_MEMBER_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _confirmRemoveMember(GroupMember member) async {
    if (!mounted) return;

    final shouldRemove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${member.username ?? 'member'} from the group?'),
        content: const Text(
          'They will stop receiving new messages from this group.',
        ),
        actions: [
          TextButton(
            key: const ValueKey('group-remove-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('group-remove-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (shouldRemove == true) {
      await _onRemoveMember(member);
    }
  }

  void _onAddMember() {
    Navigator.of(context)
        .push<int>(
          MaterialPageRoute(
            builder: (_) => ContactPickerWired(
              groupId: widget.group.id,
              groupRepo: widget.groupRepo,
              contactRepo: widget.contactRepo,
              bridge: widget.bridge,
              identityRepo: widget.identityRepo,
              p2pService: widget.p2pService,
            ),
          ),
        )
        .then((count) {
          if (count != null && count > 0) {
            _loadMembers();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    count == 1 ? 'Member invited' : '$count members invited',
                  ),
                ),
              );
            }
          }
        });
  }

  void _onBack() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return GroupInfoScreen(
      group: widget.group,
      members: _members,
      isAdmin: widget.group.myRole == GroupRole.admin,
      ownPeerId: _ownPeerId,
      onBack: _onBack,
      onLeave: _onLeave,
      onRemoveMember: widget.group.myRole == GroupRole.admin
          ? _confirmRemoveMember
          : null,
      onAddMember: widget.group.myRole == GroupRole.admin ? _onAddMember : null,
    );
  }
}
