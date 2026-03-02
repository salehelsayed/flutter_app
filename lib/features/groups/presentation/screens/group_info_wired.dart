import 'package:flutter/material.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/groups/application/leave_group_use_case.dart';
import 'package:flutter_app/features/groups/application/remove_group_member_use_case.dart';
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
      await removeGroupMember(
        bridge: widget.bridge,
        groupRepo: widget.groupRepo,
        groupId: widget.group.id,
        memberPeerId: member.peerId,
      );

      _loadMembers();
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_INFO_FL_REMOVE_MEMBER_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  void _onAddMember() {
    Navigator.of(context).push(
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
    ).then((added) {
      if (added == true) {
        _loadMembers();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Member invited')),
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
          ? _onRemoveMember
          : null,
      onAddMember: widget.group.myRole == GroupRole.admin
          ? _onAddMember
          : null,
    );
  }
}
