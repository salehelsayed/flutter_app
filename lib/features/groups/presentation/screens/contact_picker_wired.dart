import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/groups/application/add_group_member_use_case.dart';
import 'package:flutter_app/features/groups/application/send_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/groups/presentation/screens/contact_picker_screen.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

/// Wired widget that loads contacts, filters out existing members,
/// provides multi-select toggling, and batch-invites all selected contacts.
class ContactPickerWired extends StatefulWidget {
  final String groupId;
  final GroupRepository groupRepo;
  final ContactRepository contactRepo;
  final Bridge bridge;
  final IdentityRepository identityRepo;
  final P2PService p2pService;

  const ContactPickerWired({
    super.key,
    required this.groupId,
    required this.groupRepo,
    required this.contactRepo,
    required this.bridge,
    required this.identityRepo,
    required this.p2pService,
  });

  @override
  State<ContactPickerWired> createState() => _ContactPickerWiredState();
}

class _ContactPickerWiredState extends State<ContactPickerWired> {
  List<ContactModel> _availableContacts = [];
  final Set<String> _selectedPeerIds = {};
  bool _isInviting = false;

  @override
  void initState() {
    super.initState();
    _loadAvailableContacts();
  }

  Future<void> _loadAvailableContacts() async {
    // 1. Get all non-archived contacts
    final allContacts = await widget.contactRepo.getActiveContacts();

    // 2. Get current group members
    final members = await widget.groupRepo.getMembers(widget.groupId);
    final excludePeerIds = members.map((m) => m.peerId).toSet();

    // 3. Get own peerId to exclude self
    final identity = await widget.identityRepo.loadIdentity();
    if (identity != null) {
      excludePeerIds.add(identity.peerId);
    }

    // 4. Filter: only contacts NOT already in the group and not self
    if (!mounted) return;
    setState(() {
      _availableContacts = allContacts
          .where((c) => !excludePeerIds.contains(c.peerId))
          .toList()
        ..sort((a, b) => a.username.compareTo(b.username));
    });
  }

  void _onToggle(ContactModel contact) {
    setState(() {
      if (_selectedPeerIds.contains(contact.peerId)) {
        _selectedPeerIds.remove(contact.peerId);
      } else {
        _selectedPeerIds.add(contact.peerId);
      }
    });
  }

  Future<void> _inviteSelected() async {
    setState(() => _isInviting = true);

    try {
      final identity = await widget.identityRepo.loadIdentity();
      if (identity == null) throw StateError('No identity found');

      final selectedContacts = _availableContacts
          .where((c) => _selectedPeerIds.contains(c.peerId))
          .toList();

      // 1. Add all members locally (continue on individual errors)
      final addedMembers = <GroupMember>[];
      for (final contact in selectedContacts) {
        try {
          final newMember = GroupMember(
            groupId: widget.groupId,
            peerId: contact.peerId,
            username: contact.username,
            role: MemberRole.writer,
            publicKey: contact.publicKey,
            mlKemPublicKey: contact.mlKemPublicKey,
            joinedAt: DateTime.now().toUtc(),
          );
          await addGroupMember(
            bridge: widget.bridge,
            groupRepo: widget.groupRepo,
            groupId: widget.groupId,
            newMember: newMember,
            selfPeerId: identity.peerId,
          );
          addedMembers.add(newMember);
        } catch (e) {
          emitFlowEvent(
            layer: 'FL',
            event: 'CONTACT_PICKER_FL_ADD_MEMBER_ERROR',
            details: {'peerId': contact.peerId, 'error': e.toString()},
          );
        }
      }
      if (addedMembers.isEmpty) throw StateError('No members could be added');

      // 2. Build full GroupConfig and update Go topic validator ONCE
      final group = await widget.groupRepo.getGroup(widget.groupId);
      final allMembers = await widget.groupRepo.getMembers(widget.groupId);
      if (group == null) throw StateError('Group not found');

      final groupConfig = {
        'name': group.name,
        'groupType': group.type.toValue(),
        if (group.description != null) 'description': group.description,
        'members': allMembers
            .map((m) => {
                  'peerId': m.peerId,
                  'username': m.username,
                  'role': m.role.toValue(),
                  'publicKey': m.publicKey,
                  if (m.mlKemPublicKey != null)
                    'mlKemPublicKey': m.mlKemPublicKey,
                })
            .toList(),
        'createdBy': group.createdBy,
        'createdAt': group.createdAt.toUtc().toIso8601String(),
      };

      await callGroupUpdateConfig(
        widget.bridge,
        groupId: widget.groupId,
        groupConfig: groupConfig,
      );

      // 3. Broadcast ONE members_added system message
      final sysMessage = jsonEncode({
        '__sys': 'members_added',
        'members': addedMembers
            .map((m) => {
                  'peerId': m.peerId,
                  'username': m.username,
                  'role': m.role.toValue(),
                  'publicKey': m.publicKey,
                  if (m.mlKemPublicKey != null)
                    'mlKemPublicKey': m.mlKemPublicKey,
                })
            .toList(),
        'groupConfig': groupConfig,
      });

      await callGroupPublish(
        widget.bridge,
        groupId: widget.groupId,
        text: sysMessage,
        senderPeerId: identity.peerId,
        senderPublicKey: identity.publicKey,
        senderPrivateKey: identity.privateKey,
        senderUsername: identity.username ?? '',
      );

      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACT_PICKER_FL_CONFIG_BROADCAST_SENT',
        details: {
          'groupId': widget.groupId.length > 8
              ? widget.groupId.substring(0, 8)
              : widget.groupId,
          'addedCount': addedMembers.length,
        },
      );

      // 4. Send individual encrypted P2P invites in parallel
      final keyInfo = await widget.groupRepo.getLatestKey(widget.groupId);
      if (keyInfo != null) {
        final recipients = selectedContacts
            .where((c) => addedMembers.any((m) => m.peerId == c.peerId))
            .map((c) => (peerId: c.peerId, mlKemPublicKey: c.mlKemPublicKey))
            .toList();

        await sendGroupInvitesInParallel(
          p2pService: widget.p2pService,
          bridge: widget.bridge,
          senderPeerId: identity.peerId,
          senderUsername: identity.username ?? '',
          groupId: widget.groupId,
          groupKey: keyInfo.encryptedKey,
          keyEpoch: keyInfo.keyGeneration,
          groupConfig: groupConfig,
          recipients: recipients,
        );
      } else {
        emitFlowEvent(
          layer: 'FL',
          event: 'CONTACT_PICKER_FL_NO_GROUP_KEY',
          details: {
            'groupId': widget.groupId.length > 8
                ? widget.groupId.substring(0, 8)
                : widget.groupId,
          },
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop(addedMembers.length);
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACT_PICKER_FL_INVITE_ERROR',
        details: {'error': e.toString()},
      );
      if (mounted) {
        setState(() => _isInviting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to invite members')),
        );
      }
    }
  }

  void _onBack() {
    Navigator.of(context).pop(0);
  }

  @override
  Widget build(BuildContext context) {
    return ContactPickerScreen(
      contacts: _availableContacts,
      isInviting: _isInviting,
      onToggle: _onToggle,
      selectedPeerIds: _selectedPeerIds,
      onConfirm: _selectedPeerIds.isNotEmpty ? _inviteSelected : null,
      onBack: _onBack,
    );
  }
}
