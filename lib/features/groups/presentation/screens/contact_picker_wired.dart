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
import 'package:flutter_app/features/orbit/presentation/widgets/confirmation_dialog.dart';

/// Wired widget that loads contacts, filters out existing members,
/// handles selection with a confirmation dialog, adds the member locally,
/// updates the Go topic validator, and sends the encrypted group invite.
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

  Future<void> _onSelect(ContactModel contact) async {
    final confirmed = await showConfirmationDialog(
      context: context,
      title: 'Invite ${contact.username}?',
      description: 'They will be added as a member of this group.',
      confirmLabel: 'Invite',
    );
    if (!confirmed || !mounted) return;
    _inviteMember(contact);
  }

  Future<void> _inviteMember(ContactModel contact) async {
    setState(() => _isInviting = true);

    try {
      final identity = await widget.identityRepo.loadIdentity();
      if (identity == null) throw StateError('No identity found');

      final newMember = GroupMember(
        groupId: widget.groupId,
        peerId: contact.peerId,
        username: contact.username,
        role: MemberRole.writer,
        publicKey: contact.publicKey,
        mlKemPublicKey: contact.mlKemPublicKey,
        joinedAt: DateTime.now().toUtc(),
      );

      // 1. Save member to local DB
      await addGroupMember(
        bridge: widget.bridge,
        groupRepo: widget.groupRepo,
        groupId: widget.groupId,
        newMember: newMember,
        selfPeerId: identity.peerId,
      );

      // 2. Build full GroupConfig and update Go topic validator
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

      // 2b. Broadcast config update to existing members via group pubsub
      //     so they update their Go topic validator to accept the new member.
      final sysMessage = jsonEncode({
        '__sys': 'member_added',
        'member': {
          'peerId': contact.peerId,
          'username': contact.username,
          'role': 'writer',
          'publicKey': contact.publicKey,
          if (contact.mlKemPublicKey != null)
            'mlKemPublicKey': contact.mlKemPublicKey,
        },
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
          'newMemberPeerId': contact.peerId.length > 10
              ? contact.peerId.substring(0, 10)
              : contact.peerId,
        },
      );

      // 3. Send encrypted invite to the new member via 1:1 P2P
      final keyInfo = await widget.groupRepo.getLatestKey(widget.groupId);
      if (keyInfo != null) {
        emitFlowEvent(
          layer: 'FL',
          event: 'CONTACT_PICKER_FL_INVITE_SENDING',
          details: {
            'groupId': widget.groupId.length > 8
                ? widget.groupId.substring(0, 8)
                : widget.groupId,
            'recipientPeerId': contact.peerId.length > 10
                ? contact.peerId.substring(0, 10)
                : contact.peerId,
            'hasRecipientMlKemKey': contact.mlKemPublicKey != null,
            'keyEpoch': keyInfo.keyGeneration,
          },
        );

        final result = await sendGroupInvite(
          p2pService: widget.p2pService,
          bridge: widget.bridge,
          recipientPeerId: contact.peerId,
          recipientMlKemPublicKey: contact.mlKemPublicKey,
          senderPeerId: identity.peerId,
          senderUsername: identity.username ?? '',
          groupId: widget.groupId,
          groupKey: keyInfo.encryptedKey,
          keyEpoch: keyInfo.keyGeneration,
          groupConfig: groupConfig,
        );

        emitFlowEvent(
          layer: 'FL',
          event: 'CONTACT_PICKER_FL_INVITE_SEND_RESULT',
          details: {'result': result.name},
        );

        if (result != SendGroupInviteResult.success) {
          emitFlowEvent(
            layer: 'FL',
            event: 'CONTACT_PICKER_FL_INVITE_SEND_FAILED',
            details: {'result': result.name},
          );
        }
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
      Navigator.of(context).pop(true); // pop with success result
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACT_PICKER_FL_INVITE_ERROR',
        details: {'error': e.toString()},
      );
      if (mounted) {
        setState(() => _isInviting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to invite member')),
        );
      }
    }
  }

  void _onBack() {
    Navigator.of(context).pop(false); // pop with no-change result
  }

  @override
  Widget build(BuildContext context) {
    return ContactPickerScreen(
      contacts: _availableContacts,
      isInviting: _isInviting,
      onSelect: _onSelect,
      onBack: _onBack,
    );
  }
}
