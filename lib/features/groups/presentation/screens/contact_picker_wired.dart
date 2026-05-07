import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/groups/application/add_group_member_use_case.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/group_membership_timeline_message.dart';
import 'package:flutter_app/features/groups/application/record_group_invite_delivery_attempts.dart';
import 'package:flutter_app/features/groups/application/send_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/application/signed_group_transition_audit.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_membership_limit_policy.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/groups/presentation/screens/contact_picker_screen.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';

/// Wired widget that loads contacts, filters out existing members,
/// provides multi-select toggling, and batch-invites all selected contacts.
class ContactPickerInviteResult {
  final int membersAdded;
  final GroupInviteBatchResult? inviteBatchResult;
  final bool inviteDeliverySkippedMissingKey;
  final bool membersAddedPublishFailed;

  const ContactPickerInviteResult({
    required this.membersAdded,
    this.inviteBatchResult,
    this.inviteDeliverySkippedMissingKey = false,
    this.membersAddedPublishFailed = false,
  });

  const ContactPickerInviteResult.cancelled() : this(membersAdded: 0);

  int get invitesSent => inviteBatchResult?.successCount ?? 0;

  bool get hasWarnings =>
      inviteDeliverySkippedMissingKey ||
      membersAddedPublishFailed ||
      (inviteBatchResult?.hasFailures ?? false);

  String buildCompletionMessage() {
    if (!hasWarnings) {
      return membersAdded == 1
          ? 'Member invited'
          : '$membersAdded members invited';
    }

    final issues = <String>[];
    if (inviteDeliverySkippedMissingKey) {
      issues.add(
        'invites were not sent because the group is missing its latest key',
      );
    }
    if (inviteBatchResult?.hasFailures ?? false) {
      issues.add('invite issues: ${inviteBatchResult!.describeFailures()}');
    }
    if (membersAddedPublishFailed) {
      issues.add('the add-members event could not be published');
    }

    final prefix = membersAdded == 1
        ? '1 member added'
        : '$membersAdded members added';
    return '$prefix, but ${issues.join('; ')}.';
  }
}

class ContactPickerWired extends StatefulWidget {
  final String groupId;
  final GroupRepository groupRepo;
  final ContactRepository contactRepo;
  final Bridge bridge;
  final IdentityRepository identityRepo;
  final P2PService p2pService;
  final GroupMessageRepository? msgRepo;
  final GroupInviteDeliveryAttemptRepository? inviteDeliveryAttemptRepo;
  final BackgroundPreference backgroundPreference;

  const ContactPickerWired({
    super.key,
    required this.groupId,
    required this.groupRepo,
    required this.contactRepo,
    required this.bridge,
    required this.identityRepo,
    required this.p2pService,
    this.msgRepo,
    this.inviteDeliveryAttemptRepo,
    this.backgroundPreference = BackgroundPreference.defaultBackground,
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
      _availableContacts =
          allContacts.where((c) => !excludePeerIds.contains(c.peerId)).toList()
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

      final currentMembers = await widget.groupRepo.getMembers(widget.groupId);
      ensureWithinGroupMembershipLimit(
        currentMemberCount: currentMembers.length,
        requestedAdditionalMembers: selectedContacts.length,
      );
      final preTransitionStateHash = await buildGroupTransitionStateHash(
        widget.groupRepo,
        widget.groupId,
      );

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
            syncBridgeConfig: false,
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

      final groupConfig = buildGroupConfigPayload(group, allMembers);

      try {
        await callGroupUpdateConfig(
          widget.bridge,
          groupId: widget.groupId,
          groupConfig: groupConfig,
        );
      } catch (e) {
        for (final member in addedMembers) {
          await widget.groupRepo.removeMember(widget.groupId, member.peerId);
        }
        emitFlowEvent(
          layer: 'FL',
          event: 'CONTACT_PICKER_FL_CONFIG_SYNC_ROLLED_BACK',
          details: {'groupId': widget.groupId, 'error': e.toString()},
        );
        rethrow;
      }

      // 3. Broadcast ONE members_added system message
      final publishedAt = DateTime.now().toUtc();
      final sourceEventId =
          'members_added:${widget.groupId}:${identity.peerId}:${publishedAt.microsecondsSinceEpoch}';
      final sysPayload = await signGroupSystemTransitionPayload(
        bridge: widget.bridge,
        groupRepo: widget.groupRepo,
        groupId: widget.groupId,
        transitionType: 'members_added',
        sourceEventId: sourceEventId,
        eventAt: publishedAt,
        actorPeerId: identity.peerId,
        actorUsername: identity.username,
        actorSigningPublicKey: identity.publicKey,
        actorPrivateKey: identity.privateKey,
        preTransitionStateHash: preTransitionStateHash,
        systemPayload: {
          '__sys': 'members_added',
          'members': addedMembers
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
          'groupConfig': groupConfig,
        },
      );
      final sysMessage = jsonEncode(sysPayload);

      var membersAddedPublishFailed = false;
      try {
        final publishResult = await callGroupPublish(
          widget.bridge,
          groupId: widget.groupId,
          text: sysMessage,
          senderPeerId: identity.peerId,
          senderPublicKey: identity.publicKey,
          senderPrivateKey: identity.privateKey,
          senderUsername: identity.username,
          messageId: sourceEventId,
        );
        if (publishResult['ok'] != true) {
          membersAddedPublishFailed = true;
        }
      } catch (e) {
        membersAddedPublishFailed = true;
      }
      if (membersAddedPublishFailed) {
        emitFlowEvent(
          layer: 'FL',
          event: 'CONTACT_PICKER_FL_PUBLISH_WARNING',
          details: {'groupId': widget.groupId},
        );
      } else if (widget.msgRepo != null) {
        await widget.msgRepo!.saveMessage(
          buildMembersAddedTimelineMessage(
            groupId: widget.groupId,
            addedMembers: addedMembers
                .map(
                  (member) =>
                      (peerId: member.peerId, username: member.username),
                )
                .toList(growable: false),
            senderId: identity.peerId,
            senderUsername: identity.username,
            eventAt: publishedAt,
          ),
        );
      }

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
      GroupInviteBatchResult? inviteBatchResult;
      var inviteDeliverySkippedMissingKey = false;
      if (keyInfo != null) {
        final recipients = selectedContacts
            .where((c) => addedMembers.any((m) => m.peerId == c.peerId))
            .map(
              (c) => (
                peerId: c.peerId,
                username: c.username,
                mlKemPublicKey: c.mlKemPublicKey,
              ),
            )
            .toList();

        inviteBatchResult = await sendGroupInvitesInParallel(
          p2pService: widget.p2pService,
          bridge: widget.bridge,
          groupRepo: widget.groupRepo,
          senderPeerId: identity.peerId,
          senderPublicKey: identity.publicKey,
          senderPrivateKey: identity.privateKey,
          senderUsername: identity.username,
          groupId: widget.groupId,
          groupKey: keyInfo.encryptedKey,
          keyEpoch: keyInfo.keyGeneration,
          groupConfig: groupConfig,
          recipients: recipients,
        );
        await recordGroupInviteDeliveryBatch(
          inviteDeliveryAttemptRepo: widget.inviteDeliveryAttemptRepo,
          groupId: widget.groupId,
          attempts: inviteBatchResult.attempts,
        );
      } else {
        inviteDeliverySkippedMissingKey = true;
        await recordMissingGroupKeyInviteDeliveryAttempts(
          inviteDeliveryAttemptRepo: widget.inviteDeliveryAttemptRepo,
          groupId: widget.groupId,
          members: addedMembers,
        );
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
      Navigator.of(context).pop(
        ContactPickerInviteResult(
          membersAdded: addedMembers.length,
          inviteBatchResult: inviteBatchResult,
          inviteDeliverySkippedMissingKey: inviteDeliverySkippedMissingKey,
          membersAddedPublishFailed: membersAddedPublishFailed,
        ),
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACT_PICKER_FL_INVITE_ERROR',
        details: {'error': e.toString()},
      );
      if (mounted) {
        setState(() => _isInviting = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_buildInviteErrorMessage(e))));
      }
    }
  }

  String _buildInviteErrorMessage(Object error) {
    final l10n = AppLocalizations.of(context)!;
    if (error is GroupMembershipLimitException) {
      return l10n.group_invite_member_limit_reached(
        error.maxMembers,
        error.overflowCount,
      );
    }

    return l10n.group_invite_failed;
  }

  void _onBack() {
    Navigator.of(context).pop(const ContactPickerInviteResult.cancelled());
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
      backgroundPreference: widget.backgroundPreference,
    );
  }
}
