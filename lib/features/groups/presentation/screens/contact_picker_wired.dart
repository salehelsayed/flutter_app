import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/groups/application/add_group_member_use_case.dart';
import 'package:flutter_app/features/groups/application/group_avatar_storage.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/group_media_allowed_peers.dart';
import 'package:flutter_app/features/groups/application/group_membership_update_listener.dart';
import 'package:flutter_app/features/groups/application/group_membership_timeline_message.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/application/group_sender_device_binding.dart';
import 'package:flutter_app/features/groups/application/record_group_invite_delivery_attempts.dart';
import 'package:flutter_app/features/groups/application/send_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/application/signed_group_transition_audit.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_membership_limit_policy.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
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

  String buildCompletionMessage([AppLocalizations? l10n]) {
    if (!hasWarnings) {
      return l10n?.group_member_invited_count(membersAdded) ??
          (membersAdded == 1
              ? 'Member invited'
              : '$membersAdded members invited');
    }

    final issues = <String>[];
    if (inviteDeliverySkippedMissingKey) {
      issues.add(
        l10n?.group_invite_missing_key_issue ??
            'invites were not sent because the group is missing its latest key',
      );
    }
    if (inviteBatchResult?.hasFailures ?? false) {
      final details = inviteBatchResult!.describeFailures();
      issues.add(
        l10n?.group_invite_issues(details) ?? 'invite issues: $details',
      );
    }
    if (membersAddedPublishFailed) {
      issues.add(
        l10n?.group_members_publish_failed_issue ??
            'the add-members event could not be published',
      );
    }

    final prefix =
        l10n?.group_member_added_count(membersAdded) ??
        (membersAdded == 1 ? '1 member added' : '$membersAdded members added');
    final joinedIssues = issues.join('; ');
    return l10n?.group_member_added_with_warnings(prefix, joinedIssues) ??
        '$prefix, but $joinedIssues.';
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
  final UploadGroupAvatarFn uploadGroupAvatarFn;
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
    this.uploadGroupAvatarFn = uploadGroupAvatar,
    this.backgroundPreference = BackgroundPreference.defaultBackground,
  });

  @override
  State<ContactPickerWired> createState() => _ContactPickerWiredState();
}

class _ContactPickerWiredState extends State<ContactPickerWired> {
  static const _contactLoadErrorCopy = "Couldn't load contacts";

  List<ContactModel> _availableContacts = [];
  final Set<String> _selectedPeerIds = {};
  bool _isLoadingContacts = true;
  String? _contactLoadErrorMessage;
  bool _isInviting = false;

  String? get _currentSenderDeviceId {
    final peerId = widget.p2pService.currentState.peerId?.trim();
    return peerId == null || peerId.isEmpty ? null : peerId;
  }

  @override
  void initState() {
    super.initState();
    _loadAvailableContacts();
  }

  Future<void> _loadAvailableContacts() async {
    if (!_isLoadingContacts || _contactLoadErrorMessage != null) {
      setState(() {
        _isLoadingContacts = true;
        _contactLoadErrorMessage = null;
      });
    }

    try {
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
      final availableContacts =
          allContacts.where((c) => !excludePeerIds.contains(c.peerId)).toList()
            ..sort((a, b) => a.username.compareTo(b.username));

      if (!mounted) return;
      setState(() {
        _availableContacts = availableContacts;
        _isLoadingContacts = false;
        _contactLoadErrorMessage = null;
      });
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACT_PICKER_FL_LOAD_CONTACTS_ERROR',
        details: {'groupId': widget.groupId, 'error': e.toString()},
      );

      if (!mounted) return;
      setState(() {
        _isLoadingContacts = false;
        _contactLoadErrorMessage = _availableContacts.isEmpty
            ? _contactLoadErrorCopy
            : null;
      });
    }
  }

  void _retryLoadAvailableContacts() {
    _loadAvailableContacts();
  }

  void _onToggle(ContactModel contact) {
    if (!mounted) return;
    setState(() {
      if (_selectedPeerIds.contains(contact.peerId)) {
        _selectedPeerIds.remove(contact.peerId);
      } else {
        _selectedPeerIds.add(contact.peerId);
      }
    });
  }

  Future<String?> _resolveExistingAvatarUploadPath(GroupModel group) async {
    final storedPath = group.avatarPath?.trim();
    if (storedPath != null && storedPath.isNotEmpty) {
      final storedFile = File(storedPath);
      if (storedFile.isAbsolute && storedFile.existsSync()) {
        return storedPath;
      }
    }

    final canonicalPath = await groupAvatarCanonicalPath(group.id);
    if (File(canonicalPath).existsSync()) {
      return canonicalPath;
    }
    return null;
  }

  Future<GroupModel> _refreshAvatarAccessForMembers({
    required GroupModel group,
    required List<GroupMember> members,
  }) async {
    if (group.avatarBlobId == null || group.avatarMime == null) {
      return group;
    }

    final uploadPath = await _resolveExistingAvatarUploadPath(group);
    if (uploadPath == null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACT_PICKER_FL_AVATAR_REGRANT_SKIPPED',
        details: {
          'groupId': widget.groupId.length > 8
              ? widget.groupId.substring(0, 8)
              : widget.groupId,
          'reason': 'local_avatar_missing',
        },
      );
      return group;
    }

    final uploaded = await widget.uploadGroupAvatarFn(
      bridge: widget.bridge,
      localFilePath: uploadPath,
      groupId: widget.groupId,
      allowedPeers: groupMediaAllowedPeersForMembers(members),
      mime: group.avatarMime ?? 'image/jpeg',
    );
    if (uploaded == null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACT_PICKER_FL_AVATAR_REGRANT_FAILED',
        details: {
          'groupId': widget.groupId.length > 8
              ? widget.groupId.substring(0, 8)
              : widget.groupId,
        },
      );
      return group;
    }

    final updatedGroup = group.copyWith(
      avatarBlobId: uploaded.id,
      avatarMime: uploaded.mime,
      avatarPath: group.avatarPath,
    );
    await widget.groupRepo.updateGroup(updatedGroup);
    return updatedGroup;
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

      await recordPendingGroupInviteFanoutAttempts(
        inviteDeliveryAttemptRepo: widget.inviteDeliveryAttemptRepo,
        groupId: widget.groupId,
        members: addedMembers,
      );

      // 2. Build full GroupConfig and update Go topic validator ONCE
      final loadedGroup = await widget.groupRepo.getGroup(widget.groupId);
      final allMembers = await widget.groupRepo.getMembers(widget.groupId);
      if (loadedGroup == null) throw StateError('Group not found');
      final group = await _refreshAvatarAccessForMembers(
        group: loadedGroup,
        members: allMembers,
      );

      final groupConfig = buildGroupConfigPayload(group, allMembers);
      final senderBinding = await resolveGroupSenderDeviceBinding(
        groupRepo: widget.groupRepo,
        groupId: widget.groupId,
        senderPeerId: identity.peerId,
        preferredDeviceId: _currentSenderDeviceId,
        preferredTransportPeerId: _currentSenderDeviceId,
        senderPublicKey: identity.publicKey,
      );

      try {
        await callGroupUpdateConfig(
          widget.bridge,
          groupId: widget.groupId,
          groupConfig: groupConfig,
        );
      } catch (e) {
        for (final member in addedMembers) {
          await widget.groupRepo.removeMember(widget.groupId, member.peerId);
          await widget.inviteDeliveryAttemptRepo?.deleteAttempt(
            groupId: widget.groupId,
            peerId: member.peerId,
          );
        }
        if (group.avatarBlobId != loadedGroup.avatarBlobId ||
            group.avatarMime != loadedGroup.avatarMime ||
            group.avatarPath != loadedGroup.avatarPath) {
          await widget.groupRepo.updateGroup(loadedGroup);
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
        actorDeviceId: senderBinding.deviceId,
        actorTransportPeerId: senderBinding.transportPeerId,
        actorKeyPackageId: senderBinding.keyPackageId,
        preTransitionStateHash: preTransitionStateHash,
        systemPayload: {
          '__sys': 'members_added',
          'members': addedMembers.map((m) => m.toConfigJson()).toList(),
          'groupConfig': groupConfig,
        },
      );
      final sysMessage = jsonEncode(sysPayload);
      final existingRecipientPeerIds = currentMembers
          .map((member) => member.peerId)
          .where((peerId) => peerId.isNotEmpty && peerId != identity.peerId)
          .toList(growable: false);

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
          senderDeviceId: senderBinding.deviceId,
          senderTransportPeerId: senderBinding.transportPeerId,
          senderDevicePublicKey: senderBinding.devicePublicKey,
          senderKeyPackageId: senderBinding.keyPackageId,
          messageId: sourceEventId,
        );
        if (publishResult['ok'] != true) {
          membersAddedPublishFailed = true;
        }
      } catch (e) {
        membersAddedPublishFailed = true;
      }
      final keyInfo = await widget.groupRepo.getLatestKey(widget.groupId);
      if (existingRecipientPeerIds.isNotEmpty && keyInfo != null) {
        try {
          final inboxPayload = jsonEncode({
            'groupId': widget.groupId,
            'senderId': identity.peerId,
            'senderUsername': identity.username,
            if (senderBinding.deviceId != null)
              'senderDeviceId': senderBinding.deviceId,
            if (senderBinding.transportPeerId != null)
              'transportPeerId': senderBinding.transportPeerId,
            'text': sysMessage,
            'timestamp': publishedAt.toIso8601String(),
            'messageId': sourceEventId,
          });
          final replayEnvelope = await buildGroupOfflineReplayEnvelope(
            bridge: widget.bridge,
            groupRepo: widget.groupRepo,
            groupId: widget.groupId,
            payloadType: groupOfflineReplayPayloadTypeMessage,
            plaintext: inboxPayload,
            senderPeerId: identity.peerId,
            senderPublicKey: identity.publicKey,
            senderPrivateKey: identity.privateKey,
            keyInfo: keyInfo,
            senderDeviceId: senderBinding.deviceId,
            senderTransportPeerId: senderBinding.transportPeerId,
            senderKeyPackageId: senderBinding.keyPackageId,
            messageId: sourceEventId,
            recipientPeerIds: existingRecipientPeerIds,
          );
          await callGroupInboxStore(
            widget.bridge,
            widget.groupId,
            replayEnvelope,
            recipientPeerIds: existingRecipientPeerIds,
            preserveRecipientPeerIds: true,
          );
          final directTargets = groupMembershipUpdateDirectTargets(
            members: currentMembers,
            excludingPeerId: identity.peerId,
          );
          for (final target in directTargets) {
            unawaited(
              sendGroupMembershipUpdateDirect(
                sendP2PMessage: (peerId, message) =>
                    widget.p2pService.sendMessage(peerId, message),
                recipientPeerId: target.deliveryPeerId,
                groupId: widget.groupId,
                senderPeerId: identity.peerId,
                replayEnvelope: replayEnvelope,
                timestamp: publishedAt,
                messageId: sourceEventId,
              ),
            );
          }
        } catch (e) {
          membersAddedPublishFailed = true;
          emitFlowEvent(
            layer: 'FL',
            event: 'CONTACT_PICKER_FL_MEMBERSHIP_REPLAY_WARNING',
            details: {'groupId': widget.groupId, 'error': e.toString()},
          );
        }
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
          senderDeviceId: senderBinding.deviceId,
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
      isLoadingContacts: _isLoadingContacts,
      contactLoadErrorMessage: _contactLoadErrorMessage,
      onRetryLoadContacts: _retryLoadAvailableContacts,
      isInviting: _isInviting,
      onToggle: _onToggle,
      selectedPeerIds: _selectedPeerIds,
      onConfirm: _selectedPeerIds.isNotEmpty ? _inviteSelected : null,
      onBack: _onBack,
      backgroundPreference: widget.backgroundPreference,
    );
  }
}
