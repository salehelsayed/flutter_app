import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_picker.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/groups/application/broadcast_voluntary_leave_use_case.dart';
import 'package:flutter_app/features/groups/application/group_avatar_storage.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/dissolve_group_use_case.dart';
import 'package:flutter_app/features/groups/application/delete_group_and_messages_use_case.dart';
import 'package:flutter_app/features/groups/application/group_membership_timeline_message.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/application/leave_group_use_case.dart';
import 'package:flutter_app/features/groups/application/remove_group_member_use_case.dart';
import 'package:flutter_app/features/groups/application/resend_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/application/rotate_and_distribute_group_key_use_case.dart';
import 'package:flutter_app/features/groups/application/set_group_muted_use_case.dart';
import 'package:flutter_app/features/groups/application/signed_group_transition_audit.dart';
import 'package:flutter_app/features/groups/application/update_group_metadata_use_case.dart';
import 'package:flutter_app/features/groups/application/update_group_member_role_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_delivery_attempt.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_member_identity_safety.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/groups/presentation/group_security_status_view_state.dart';
import 'package:flutter_app/features/groups/presentation/screens/contact_picker_wired.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_info_screen.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_avatar.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/settings/application/helpers/avatar_normalization_helper.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';

/// Wired widget connecting GroupInfoScreen to business logic.
class GroupInfoWired extends StatefulWidget {
  final GroupModel group;
  final GroupRepository groupRepo;
  final ContactRepository contactRepo;
  final Bridge bridge;
  final IdentityRepository identityRepo;
  final P2PService p2pService;
  final GroupMessageRepository? msgRepo;
  final GroupInviteDeliveryAttemptRepository? inviteDeliveryAttemptRepo;
  final ImageProcessor? imageProcessor;
  final MediaPicker? mediaPicker;
  final UploadMediaFn uploadMediaFn;
  final BackgroundPreference backgroundPreference;

  const GroupInfoWired({
    super.key,
    required this.group,
    required this.groupRepo,
    required this.contactRepo,
    required this.bridge,
    required this.identityRepo,
    required this.p2pService,
    this.msgRepo,
    this.inviteDeliveryAttemptRepo,
    this.imageProcessor,
    this.mediaPicker,
    this.uploadMediaFn = uploadMedia,
    this.backgroundPreference = BackgroundPreference.defaultBackground,
  });

  @override
  State<GroupInfoWired> createState() => _GroupInfoWiredState();
}

class _GroupInfoWiredState extends State<GroupInfoWired> {
  static final MediaPicker _defaultMediaPicker = SystemMediaPicker();

  late GroupModel _group;
  List<GroupMember> _members = [];
  Map<String, GroupInviteDeliveryStatus> _inviteStatusesByPeerId = {};
  final Set<String> _resendingInvitePeerIds = {};
  Map<String, GroupMemberIdentitySafety> _memberSafetyByPeerId = {};
  GroupSecurityStatusViewState? _securityStatus;
  String? _ownPeerId;
  bool _didMutateGroup = false;
  bool _isUpdatingMute = false;
  bool _isDissolving = false;
  bool _isDeletingLocally = false;

  MediaPicker get _mediaPicker => widget.mediaPicker ?? _defaultMediaPicker;

  @override
  void initState() {
    super.initState();
    _group = widget.group;
    _loadGroupInfo();
    _loadIdentity();
  }

  Future<void> _loadIdentity() async {
    final identity = await widget.identityRepo.loadIdentity();
    if (identity != null && mounted) {
      setState(() => _ownPeerId = identity.peerId);
    }
  }

  Future<void> _loadGroupInfo() async {
    try {
      final identity = _ownPeerId == null
          ? await widget.identityRepo.loadIdentity()
          : null;
      final ownPeerId = _ownPeerId ?? identity?.peerId;
      final group = await widget.groupRepo.getGroup(widget.group.id);
      final members = await widget.groupRepo.getMembers(widget.group.id);
      final inviteStatusesByPeerId =
          await widget.inviteDeliveryAttemptRepo?.getStatusesForGroupMembers(
            widget.group.id,
          ) ??
          const <String, GroupInviteDeliveryStatus>{};
      final memberSafetyByPeerId = await _loadMemberSafety(
        members,
        ownPeerId: ownPeerId,
      );
      final latestKey = await widget.groupRepo.getLatestKey(widget.group.id);
      final securityStatus = GroupSecurityStatusViewState.fromSnapshot(
        latestKey: latestKey,
        memberCount: members.length,
        memberSafety: memberSafetyByPeerId.values,
        locallyVerifiedMemberCount:
            ownPeerId != null &&
                members.any((member) => member.peerId == ownPeerId)
            ? 1
            : 0,
      );
      if (!mounted) return;
      setState(() {
        if (group != null) {
          _group = group;
        }
        if (_ownPeerId == null && ownPeerId != null) {
          _ownPeerId = ownPeerId;
        }
        _members = members;
        _inviteStatusesByPeerId = inviteStatusesByPeerId;
        _memberSafetyByPeerId = memberSafetyByPeerId;
        _securityStatus = securityStatus;
      });
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_INFO_FL_LOAD_MEMBERS_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<Map<String, GroupMemberIdentitySafety>> _loadMemberSafety(
    List<GroupMember> members, {
    String? ownPeerId,
  }) async {
    final memberSafetyByPeerId = <String, GroupMemberIdentitySafety>{};
    for (final member in members) {
      if (member.peerId == ownPeerId) {
        continue;
      }
      try {
        final contact = await widget.contactRepo.getContact(member.peerId);
        final safety = GroupMemberIdentitySafety.compare(
          member: member,
          savedContact: contact,
        );
        if (safety != null) {
          memberSafetyByPeerId[member.peerId] = safety;
        }
      } catch (e) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_INFO_FL_MEMBER_SAFETY_ERROR',
          details: {
            'peerId': member.peerId.length > 10
                ? member.peerId.substring(0, 10)
                : member.peerId,
            'error': e.toString(),
          },
        );
      }
    }
    return memberSafetyByPeerId;
  }

  Future<void> _onLeave() async {
    try {
      await _broadcastSelfRemovalIfNeeded();
      await leaveGroup(
        bridge: widget.bridge,
        groupRepo: widget.groupRepo,
        groupId: _group.id,
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
      if (!mounted) return;
      final message = e is StateError && e.message != null
          ? e.message.toString()
          : 'Failed to leave group';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _onMuteChanged(bool isMuted) async {
    if (_isUpdatingMute) {
      return;
    }

    setState(() => _isUpdatingMute = true);
    try {
      final updatedGroup = await setGroupMuted(
        groupRepo: widget.groupRepo,
        groupId: _group.id,
        isMuted: isMuted,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _group = updatedGroup;
        _didMutateGroup = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isMuted
                ? 'Notifications muted for this group'
                : 'Notifications restored for this group',
          ),
        ),
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_INFO_FL_MUTE_UPDATE_ERROR',
        details: {
          'groupId': _group.id.length > 8
              ? _group.id.substring(0, 8)
              : _group.id,
          'error': e.toString(),
        },
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to update mute')));
      await _loadGroupInfo();
    } finally {
      if (mounted) {
        setState(() => _isUpdatingMute = false);
      }
    }
  }

  Future<void> _confirmDissolveGroup() async {
    if (!mounted || _isDissolving) return;

    final shouldDissolve = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Dissolve this group for everyone?'),
        content: const Text(
          'This ends the group for all members. History stays visible, but no one can send new messages after it is dissolved.',
        ),
        actions: [
          TextButton(
            key: const ValueKey('group-dissolve-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('group-dissolve-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Dissolve'),
          ),
        ],
      ),
    );

    if (shouldDissolve == true) {
      await _onDissolveGroup();
    }
  }

  Future<void> _onDissolveGroup() async {
    if (_isDissolving || widget.msgRepo == null) {
      return;
    }

    setState(() => _isDissolving = true);

    try {
      final identity = await widget.identityRepo.loadIdentity();
      if (identity == null) {
        throw StateError('No identity found');
      }

      final (result, _) = await dissolveGroup(
        bridge: widget.bridge,
        groupRepo: widget.groupRepo,
        msgRepo: widget.msgRepo!,
        groupId: _group.id,
        actorPeerId: identity.peerId,
        actorUsername: identity.username ?? '',
        actorPublicKey: identity.publicKey,
        actorPrivateKey: identity.privateKey,
      );

      switch (result) {
        case DissolveGroupResult.success:
          _didMutateGroup = true;
          await _loadGroupInfo();
          if (!mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Group dissolved')));
          break;
        case DissolveGroupResult.bridgeError:
          _didMutateGroup = true;
          await _loadGroupInfo();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Group dissolved. Some members may need recovery to see it.',
              ),
            ),
          );
          break;
        case DissolveGroupResult.alreadyDissolved:
          _didMutateGroup = true;
          await _loadGroupInfo();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Group already dissolved')),
          );
          break;
        case DissolveGroupResult.unauthorized:
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Only admins can dissolve groups')),
          );
          break;
        case DissolveGroupResult.notFound:
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Group no longer exists')),
          );
          break;
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_INFO_FL_DISSOLVE_ERROR',
        details: {
          'groupId': _group.id.length > 8
              ? _group.id.substring(0, 8)
              : _group.id,
          'error': e.toString(),
        },
      );
      if (!mounted) return;
      final message = e is StateError && e.message != null
          ? e.message.toString()
          : 'Failed to dissolve group';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      await _loadGroupInfo();
    } finally {
      if (mounted) {
        setState(() => _isDissolving = false);
      } else {
        _isDissolving = false;
      }
    }
  }

  Future<void> _confirmDeleteGroupLocally() async {
    if (!mounted || _isDeletingLocally || widget.msgRepo == null) return;

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this dissolved group from this device?'),
        content: const Text(
          'This removes the dissolved history from this device only. It will not affect anyone else or send a new leave event.',
        ),
        actions: [
          TextButton(
            key: const ValueKey('group-delete-local-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('group-delete-local-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete Locally'),
          ),
        ],
      ),
    );

    if (shouldDelete == true) {
      await _onDeleteGroupLocally();
    }
  }

  Future<void> _onDeleteGroupLocally() async {
    if (_isDeletingLocally || widget.msgRepo == null) {
      return;
    }

    setState(() => _isDeletingLocally = true);

    try {
      await deleteGroupAndMessages(
        bridge: widget.bridge,
        groupRepo: widget.groupRepo,
        groupMessageRepo: widget.msgRepo!,
        groupId: _group.id,
        deleteLocallyIfDissolved: true,
      );

      _didMutateGroup = true;
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_INFO_FL_DELETE_LOCAL_DISSOLVED_ERROR',
        details: {
          'groupId': _group.id.length > 8
              ? _group.id.substring(0, 8)
              : _group.id,
          'error': e.toString(),
        },
      );
      if (!mounted) return;
      final message = e is StateError && e.message != null
          ? e.message.toString()
          : 'Failed to delete group locally';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        setState(() => _isDeletingLocally = false);
      } else {
        _isDeletingLocally = false;
      }
    }
  }

  Future<void> _broadcastSelfRemovalIfNeeded() async {
    await broadcastVoluntaryLeaveAndRotateKey(
      bridge: widget.bridge,
      groupRepo: widget.groupRepo,
      group: _group,
      identityRepo: widget.identityRepo,
      msgRepo: widget.msgRepo,
      sendP2PMessage: (peerId, message) async {
        await widget.p2pService.sendMessage(peerId, message);
        return true;
      },
    );
  }

  Future<void> _onRemoveMember(GroupMember member) async {
    try {
      final removedAt = DateTime.now().toUtc();
      final identity = await widget.identityRepo.loadIdentity();
      final preTransitionStateHash = await buildGroupTransitionStateHash(
        widget.groupRepo,
        widget.group.id,
      );

      // 1. Remove from DB + update admin's Go config
      await removeGroupMember(
        bridge: widget.bridge,
        groupRepo: widget.groupRepo,
        groupId: widget.group.id,
        memberPeerId: member.peerId,
        selfPeerId: identity?.peerId,
        eventAt: removedAt,
      );

      // 2. Broadcast member_removed system message to remaining members
      if (identity != null) {
        final group = await widget.groupRepo.getGroup(widget.group.id);
        final allMembers = await widget.groupRepo.getMembers(widget.group.id);

        if (group != null) {
          final groupConfig = buildGroupConfigPayload(group, allMembers);

          final sourceEventId =
              'member_removed:${widget.group.id}:${identity.peerId}:${removedAt.microsecondsSinceEpoch}';
          final sysPayload = await signGroupSystemTransitionPayload(
            bridge: widget.bridge,
            groupRepo: widget.groupRepo,
            groupId: widget.group.id,
            transitionType: 'member_removed',
            sourceEventId: sourceEventId,
            eventAt: removedAt,
            actorPeerId: identity.peerId,
            actorUsername: identity.username ?? '',
            actorSigningPublicKey: identity.publicKey,
            actorPrivateKey: identity.privateKey,
            preTransitionStateHash: preTransitionStateHash,
            systemPayload: {
              '__sys': 'member_removed',
              'member': {'peerId': member.peerId, 'username': member.username},
              'removedAt': removedAt.toIso8601String(),
              'groupConfig': groupConfig,
            },
          );
          final sysMessage = jsonEncode(sysPayload);
          final removalTimelineMessage = buildMemberRemovedTimelineMessage(
            groupId: widget.group.id,
            removedPeerId: member.peerId,
            removedUsername: member.username,
            senderId: identity.peerId,
            senderUsername: identity.username ?? '',
            eventAt: removedAt,
          );
          if (widget.msgRepo != null) {
            await widget.msgRepo!.saveMessage(removalTimelineMessage);
          }
          final removalInboxPayload = jsonEncode({
            'groupId': widget.group.id,
            'senderId': identity.peerId,
            'senderUsername': identity.username ?? '',
            'text': sysMessage,
            'timestamp': removedAt.toIso8601String(),
            'messageId': sourceEventId,
          });

          await callGroupPublish(
            widget.bridge,
            groupId: widget.group.id,
            text: sysMessage,
            senderPeerId: identity.peerId,
            senderPublicKey: identity.publicKey,
            senderPrivateKey: identity.privateKey,
            senderUsername: identity.username ?? '',
            messageId: sourceEventId,
          );
          await storeGroupOfflineReplayEnvelope(
            bridge: widget.bridge,
            groupRepo: widget.groupRepo,
            groupId: widget.group.id,
            payloadType: groupOfflineReplayPayloadTypeMessage,
            plaintext: removalInboxPayload,
            senderPeerId: identity.peerId,
            senderPublicKey: identity.publicKey,
            senderPrivateKey: identity.privateKey,
            messageId: removalTimelineMessage.id,
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

      _didMutateGroup = true;
      await _loadGroupInfo();
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_INFO_FL_REMOVE_MEMBER_ERROR',
        details: {'error': e.toString()},
      );
      if (!mounted) return;
      final message = e is StateError && e.message != null
          ? e.message.toString()
          : 'Failed to remove member';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      await _loadGroupInfo();
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

  Future<void> _onToggleAdminRole(GroupMember member) async {
    final nextRole = member.role == MemberRole.admin
        ? MemberRole.writer
        : MemberRole.admin;
    final changedAt = DateTime.now().toUtc();

    try {
      final identity = await widget.identityRepo.loadIdentity();
      if (identity == null) {
        throw StateError('No identity found');
      }
      final preTransitionStateHash = await buildGroupTransitionStateHash(
        widget.groupRepo,
        _group.id,
      );

      await updateGroupMemberRole(
        bridge: widget.bridge,
        groupRepo: widget.groupRepo,
        groupId: _group.id,
        memberPeerId: member.peerId,
        role: nextRole,
        selfPeerId: identity.peerId,
        eventAt: changedAt,
      );

      final group = await widget.groupRepo.getGroup(_group.id);
      final updatedMember = await widget.groupRepo.getMember(
        _group.id,
        member.peerId,
      );
      final members = await widget.groupRepo.getMembers(_group.id);

      if (group == null || updatedMember == null) {
        throw StateError('Member not found');
      }

      final sourceEventId =
          'member_role_updated:${_group.id}:${identity.peerId}:${changedAt.microsecondsSinceEpoch}';
      final sysPayload = await signGroupSystemTransitionPayload(
        bridge: widget.bridge,
        groupRepo: widget.groupRepo,
        groupId: _group.id,
        transitionType: 'member_role_updated',
        sourceEventId: sourceEventId,
        eventAt: changedAt,
        actorPeerId: identity.peerId,
        actorUsername: identity.username ?? '',
        actorSigningPublicKey: identity.publicKey,
        actorPrivateKey: identity.privateKey,
        preTransitionStateHash: preTransitionStateHash,
        systemPayload: {
          '__sys': 'member_role_updated',
          'member': {
            'peerId': updatedMember.peerId,
            'username': updatedMember.username,
            'role': updatedMember.role.toValue(),
            'publicKey': updatedMember.publicKey,
            if (updatedMember.mlKemPublicKey != null)
              'mlKemPublicKey': updatedMember.mlKemPublicKey,
          },
          'groupConfig': _buildGroupConfig(group, members),
        },
      );
      final sysText = jsonEncode(sysPayload);
      final roleTimelineMessage = buildMemberRoleUpdatedTimelineMessage(
        groupId: _group.id,
        updatedPeerId: updatedMember.peerId,
        updatedUsername: updatedMember.username,
        previousRole: member.role,
        newRole: updatedMember.role,
        senderId: identity.peerId,
        senderUsername: identity.username ?? '',
        eventAt: changedAt,
      );

      if (widget.msgRepo != null) {
        await widget.msgRepo!.saveMessage(roleTimelineMessage);
      }

      await callGroupPublish(
        widget.bridge,
        groupId: _group.id,
        text: sysText,
        senderPeerId: identity.peerId,
        senderPublicKey: identity.publicKey,
        senderPrivateKey: identity.privateKey,
        senderUsername: identity.username ?? '',
        messageId: sourceEventId,
      );

      final recipientPeerIds = members
          .where((groupMember) => groupMember.peerId != identity.peerId)
          .map((groupMember) => groupMember.peerId)
          .toList();

      if (recipientPeerIds.isNotEmpty) {
        final inboxPayload = jsonEncode({
          'groupId': _group.id,
          'senderId': identity.peerId,
          'senderUsername': identity.username ?? '',
          'text': sysText,
          'timestamp': changedAt.toIso8601String(),
          'messageId': sourceEventId,
        });
        await storeGroupOfflineReplayEnvelope(
          bridge: widget.bridge,
          groupRepo: widget.groupRepo,
          groupId: _group.id,
          payloadType: groupOfflineReplayPayloadTypeMessage,
          plaintext: inboxPayload,
          senderPeerId: identity.peerId,
          senderPublicKey: identity.publicKey,
          senderPrivateKey: identity.privateKey,
          messageId: roleTimelineMessage.id,
          recipientPeerIds: recipientPeerIds,
        );
      }

      _didMutateGroup = true;
      await _loadGroupInfo();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            updatedMember.role == MemberRole.admin
                ? '${_displayName(updatedMember)} is now an admin'
                : '${_displayName(updatedMember)} is no longer an admin',
          ),
        ),
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_INFO_FL_ROLE_CHANGE_ERROR',
        details: {
          'groupId': _group.id.length > 8
              ? _group.id.substring(0, 8)
              : _group.id,
          'peerId': member.peerId.length > 10
              ? member.peerId.substring(0, 10)
              : member.peerId,
          'error': e.toString(),
        },
      );
      if (!mounted) return;
      final message = e is StateError && e.message != null
          ? e.message.toString()
          : 'Failed to update member role';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      await _loadGroupInfo();
    }
  }

  Future<void> _confirmRoleChange(GroupMember member) async {
    if (!mounted) return;

    final isPromoting = member.role != MemberRole.admin;
    final title = isPromoting
        ? 'Make ${_displayName(member)} an admin?'
        : 'Remove admin access from ${_displayName(member)}?';
    final content = isPromoting
        ? 'They will be able to add, remove, and manage members.'
        : 'They will lose admin-only actions after the change syncs.';

    final shouldChangeRole = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            key: const ValueKey('group-role-change-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('group-role-change-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(isPromoting ? 'Make Admin' : 'Remove Admin'),
          ),
        ],
      ),
    );

    if (shouldChangeRole == true) {
      await _onToggleAdminRole(member);
    }
  }

  Future<void> _onEditDetails() async {
    final result = await showDialog<_GroupMetadataEditResult>(
      context: context,
      builder: (context) {
        final readableColors = context.backgroundReadableColors;
        return Dialog(
          backgroundColor: readableColors.surfaceBase,
          insetPadding: const EdgeInsets.all(16),
          child: _GroupMetadataEditorSheet(
            group: _group,
            mediaPicker: _mediaPicker,
            imageProcessor: widget.imageProcessor,
          ),
        );
      },
    );

    if (result == null) {
      return;
    }

    await _applyMetadataEdit(result);
  }

  Future<void> _applyMetadataEdit(_GroupMetadataEditResult edit) async {
    final resolvedName = edit.name.trim();
    final resolvedDescription = _normalizeDescription(edit.description);
    final currentDescription = _normalizeDescription(_group.description);
    final isRemovingAvatar =
        edit.removeAvatar &&
        (_group.avatarBlobId != null || _group.avatarPath != null);
    final isReplacingAvatar = edit.preparedAvatarPath != null;
    final hasMetadataChanges =
        resolvedName != _group.name ||
        resolvedDescription != currentDescription ||
        isRemovingAvatar ||
        isReplacingAvatar;

    if (!hasMetadataChanges) {
      return;
    }

    final changedAt = DateTime.now().toUtc();

    try {
      final identity = await widget.identityRepo.loadIdentity();
      if (identity == null) {
        throw StateError('No identity found');
      }
      final preTransitionStateHash = await buildGroupTransitionStateHash(
        widget.groupRepo,
        _group.id,
      );

      final members = await widget.groupRepo.getMembers(_group.id);
      final allowedPeers = members.isEmpty
          ? <String>[identity.peerId]
          : members.map((member) => member.peerId).toList();

      String? avatarBlobId = _group.avatarBlobId;
      String? avatarMime = _group.avatarMime;
      String? avatarPath = _group.avatarPath;

      if (isRemovingAvatar) {
        await deleteGroupAvatar(
          storedPath: _group.avatarPath,
          groupId: _group.id,
        );
        avatarBlobId = null;
        avatarMime = null;
        avatarPath = null;
      }

      if (isReplacingAvatar) {
        final uploaded = await widget.uploadMediaFn(
          bridge: widget.bridge,
          localFilePath: edit.preparedAvatarPath!,
          mime: 'image/jpeg',
          recipientPeerId: _group.id,
          allowedPeers: allowedPeers,
        );
        if (uploaded == null) {
          throw StateError('Failed to upload group photo');
        }

        await commitPreparedGroupAvatar(
          groupId: _group.id,
          sourcePath: edit.preparedAvatarPath!,
          avatarNormalizer: AvatarNormalizationHelper(
            imageProcessor: widget.imageProcessor,
          ),
        );

        avatarBlobId = uploaded.id;
        avatarMime = uploaded.mime;
        avatarPath = groupAvatarRelativePath(_group.id);
      }

      List<GroupMember>? refreshedMembers;
      String? sysText;

      await updateGroupMetadata(
        groupRepo: widget.groupRepo,
        groupId: _group.id,
        name: resolvedName,
        description: resolvedDescription,
        avatarBlobId: avatarBlobId,
        avatarMime: avatarMime,
        avatarPath: avatarPath,
        eventAt: changedAt,
        beforePersist: (updatedGroup) async {
          final membersForConfig = await widget.groupRepo.getMembers(_group.id);
          final groupConfig = buildGroupConfigPayload(
            updatedGroup,
            membersForConfig,
          );
          final actorPayload = buildGroupMetadataActorEventPayload(
            groupId: _group.id,
            updatedAt: changedAt,
            actorPeerId: identity.peerId,
            actorUsername: identity.username ?? '',
            actorPublicKey: identity.publicKey,
            groupConfig: groupConfig,
          );
          final canonicalPayload = canonicalizeGroupMetadataActorEventPayload(
            actorPayload,
          );
          final signResponse = await callSignPayload(
            bridge: widget.bridge,
            dataToSign: canonicalPayload,
            privateKey: identity.privateKey,
          );
          final signature = signResponse['signature'];
          if (signResponse['ok'] != true ||
              signature is! String ||
              signature.isEmpty) {
            throw StateError('Failed to sign group metadata update');
          }

          refreshedMembers = membersForConfig;
          final sourceEventId =
              'group_metadata_updated:${_group.id}:${identity.peerId}:${changedAt.microsecondsSinceEpoch}';
          final unsignedPayload = {
            '__sys': 'group_metadata_updated',
            'updatedAt': changedAt.toIso8601String(),
            'groupConfig': groupConfig,
            groupMetadataActorEventEnvelopeField:
                buildSignedGroupMetadataActorEventEnvelope(
                  signedPayload: canonicalPayload,
                  signature: signature,
                ),
          };
          final signedPayload = await signGroupSystemTransitionPayload(
            bridge: widget.bridge,
            groupRepo: widget.groupRepo,
            groupId: _group.id,
            transitionType: 'group_metadata_updated',
            sourceEventId: sourceEventId,
            eventAt: changedAt,
            actorPeerId: identity.peerId,
            actorUsername: identity.username ?? '',
            actorSigningPublicKey: identity.publicKey,
            actorPrivateKey: identity.privateKey,
            preTransitionStateHash: preTransitionStateHash,
            systemPayload: unsignedPayload,
          );
          sysText = jsonEncode(signedPayload);
        },
      );

      final signedSysText = sysText;
      final signedMembers = refreshedMembers;
      if (signedSysText == null || signedMembers == null) {
        throw StateError('Failed to sign group metadata update');
      }
      final metadataTimelineMessage = buildGroupMetadataUpdatedTimelineMessage(
        groupId: _group.id,
        senderId: identity.peerId,
        senderUsername: identity.username ?? '',
        eventAt: changedAt,
      );

      if (widget.msgRepo != null) {
        await widget.msgRepo!.saveMessage(metadataTimelineMessage);
      }

      await callGroupPublish(
        widget.bridge,
        groupId: _group.id,
        text: signedSysText,
        senderPeerId: identity.peerId,
        senderPublicKey: identity.publicKey,
        senderPrivateKey: identity.privateKey,
        senderUsername: identity.username ?? '',
        messageId:
            'group_metadata_updated:${_group.id}:${identity.peerId}:${changedAt.microsecondsSinceEpoch}',
      );

      final recipientPeerIds = signedMembers
          .where((member) => member.peerId != identity.peerId)
          .map((member) => member.peerId)
          .toList();
      if (recipientPeerIds.isNotEmpty) {
        final inboxPayload = jsonEncode({
          'groupId': _group.id,
          'senderId': identity.peerId,
          'senderUsername': identity.username ?? '',
          'text': signedSysText,
          'timestamp': changedAt.toIso8601String(),
          'messageId':
              'group_metadata_updated:${_group.id}:${identity.peerId}:${changedAt.microsecondsSinceEpoch}',
        });
        await storeGroupOfflineReplayEnvelope(
          bridge: widget.bridge,
          groupRepo: widget.groupRepo,
          groupId: _group.id,
          payloadType: groupOfflineReplayPayloadTypeMessage,
          plaintext: inboxPayload,
          senderPeerId: identity.peerId,
          senderPublicKey: identity.publicKey,
          senderPrivateKey: identity.privateKey,
          messageId: metadataTimelineMessage.id,
          recipientPeerIds: recipientPeerIds,
        );
      }

      _didMutateGroup = true;
      await _loadGroupInfo();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Group details updated')));
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_INFO_FL_METADATA_UPDATE_ERROR',
        details: {
          'groupId': _group.id.length > 8
              ? _group.id.substring(0, 8)
              : _group.id,
          'error': e.toString(),
        },
      );
      if (!mounted) return;
      final message = e is StateError && e.message != null
          ? e.message.toString()
          : 'Failed to update group details';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      await _loadGroupInfo();
    }
  }

  void _onAddMember() {
    Navigator.of(context)
        .push<ContactPickerInviteResult>(
          MaterialPageRoute(
            builder: (_) => ContactPickerWired(
              groupId: _group.id,
              groupRepo: widget.groupRepo,
              contactRepo: widget.contactRepo,
              bridge: widget.bridge,
              identityRepo: widget.identityRepo,
              p2pService: widget.p2pService,
              msgRepo: widget.msgRepo,
              inviteDeliveryAttemptRepo: widget.inviteDeliveryAttemptRepo,
              backgroundPreference: widget.backgroundPreference,
            ),
          ),
        )
        .then((result) {
          if (result != null && result.membersAdded > 0) {
            _didMutateGroup = true;
            _loadGroupInfo();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(result.buildCompletionMessage())),
              );
            }
          }
        });
  }

  Future<void> _onResendInvite(GroupMember member) async {
    final repo = widget.inviteDeliveryAttemptRepo;
    if (repo == null || _resendingInvitePeerIds.contains(member.peerId)) {
      return;
    }

    setState(() => _resendingInvitePeerIds.add(member.peerId));
    try {
      final identity = await widget.identityRepo.loadIdentity();
      if (identity == null) {
        throw StateError('No identity found');
      }
      final result = await resendGroupInvite(
        p2pService: widget.p2pService,
        bridge: widget.bridge,
        groupRepo: widget.groupRepo,
        inviteDeliveryAttemptRepo: repo,
        identity: identity,
        groupId: _group.id,
        memberPeerId: member.peerId,
      );
      await _loadGroupInfo();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_resendInviteMessage(member, result))),
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_INFO_FL_RESEND_INVITE_ERROR',
        details: {
          'groupId': _group.id.length > 8
              ? _group.id.substring(0, 8)
              : _group.id,
          'peerId': member.peerId.length > 10
              ? member.peerId.substring(0, 10)
              : member.peerId,
          'error': e.toString(),
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to resend invite')));
      await _loadGroupInfo();
    } finally {
      if (mounted) {
        setState(() => _resendingInvitePeerIds.remove(member.peerId));
      } else {
        _resendingInvitePeerIds.remove(member.peerId);
      }
    }
  }

  String _resendInviteMessage(
    GroupMember member,
    ResendGroupInviteResult result,
  ) {
    final name = _displayName(member);
    switch (result.status) {
      case GroupInviteDeliveryStatus.sent:
        return 'Invite sent to $name';
      case GroupInviteDeliveryStatus.queued:
        return 'Invite queued for $name';
      case GroupInviteDeliveryStatus.needsResend:
        return 'Invite still needs resend';
      case GroupInviteDeliveryStatus.cannotSend:
        return 'Invite cannot be sent yet';
      case GroupInviteDeliveryStatus.joined:
        return '$name already joined';
      case GroupInviteDeliveryStatus.unknown:
        return 'Invite status unknown';
    }
  }

  void _onBack() {
    Navigator.of(context).pop(_didMutateGroup);
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = _group.myRole == GroupRole.admin;
    final canManageGroup = isAdmin && !_group.isDissolved;
    final canDeleteLocally =
        _group.isDissolved && widget.msgRepo != null && !_isDeletingLocally;

    return GroupInfoScreen(
      group: _group,
      members: _members,
      inviteStatusesByPeerId: _inviteStatusesByPeerId,
      resendingInvitePeerIds: _resendingInvitePeerIds,
      memberSafetyByPeerId: _memberSafetyByPeerId,
      securityStatus: _securityStatus,
      isAdmin: isAdmin,
      ownPeerId: _ownPeerId,
      isMuted: _group.isMuted,
      isUpdatingMute: _isUpdatingMute,
      onBack: _onBack,
      onLeave: _onLeave,
      onMuteChanged: _onMuteChanged,
      onEditDetails: canManageGroup ? _onEditDetails : null,
      onDissolve: canManageGroup && widget.msgRepo != null && !_isDissolving
          ? _confirmDissolveGroup
          : null,
      onDeleteLocally: canDeleteLocally ? _confirmDeleteGroupLocally : null,
      onRemoveMember: canManageGroup ? _confirmRemoveMember : null,
      onToggleAdminRole: canManageGroup ? _confirmRoleChange : null,
      onAddMember: canManageGroup ? _onAddMember : null,
      onResendInvite: canManageGroup && widget.inviteDeliveryAttemptRepo != null
          ? _onResendInvite
          : null,
      backgroundPreference: widget.backgroundPreference,
    );
  }

  Map<String, dynamic> _buildGroupConfig(
    GroupModel group,
    List<GroupMember> members,
  ) {
    return buildGroupConfigPayload(group, members);
  }

  String _displayName(GroupMember member) {
    final username = member.username?.trim();
    if (username != null && username.isNotEmpty) {
      return username;
    }
    return 'member';
  }

  String? _normalizeDescription(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}

class _GroupMetadataEditResult {
  final String name;
  final String? description;
  final String? preparedAvatarPath;
  final bool removeAvatar;

  const _GroupMetadataEditResult({
    required this.name,
    required this.description,
    required this.preparedAvatarPath,
    required this.removeAvatar,
  });
}

class _GroupMetadataEditorSheet extends StatefulWidget {
  final GroupModel group;
  final MediaPicker mediaPicker;
  final ImageProcessor? imageProcessor;

  const _GroupMetadataEditorSheet({
    required this.group,
    required this.mediaPicker,
    required this.imageProcessor,
  });

  @override
  State<_GroupMetadataEditorSheet> createState() =>
      _GroupMetadataEditorSheetState();
}

class _GroupMetadataEditorSheetState extends State<_GroupMetadataEditorSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  String? _preparedAvatarPath;
  Uint8List? _previewBytes;
  bool _removeAvatar = false;
  bool _isPickingImage = false;

  bool get _hasCurrentAvatar =>
      widget.group.avatarBlobId != null ||
      widget.group.avatarPath != null ||
      _previewBytes != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.group.name);
    _descriptionController = TextEditingController(
      text: widget.group.description ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    setState(() => _isPickingImage = true);

    try {
      final picked = await widget.mediaPicker.pickImage(
        source: ImageSource.gallery,
      );
      if (picked == null || !mounted) {
        return;
      }

      final avatarNormalizer = AvatarNormalizationHelper(
        imageProcessor: widget.imageProcessor,
      );
      final preparedPath = await avatarNormalizer.prepareAvatar(
        inputPath: picked.path,
      );
      final bytes = await File(preparedPath).readAsBytes();
      if (!mounted) return;
      setState(() {
        _preparedAvatarPath = preparedPath;
        _previewBytes = bytes;
        _removeAvatar = false;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to pick group photo')),
      );
    } finally {
      if (mounted) {
        setState(() => _isPickingImage = false);
      }
    }
  }

  void _removePhoto() {
    setState(() {
      _preparedAvatarPath = null;
      _previewBytes = null;
      _removeAvatar = true;
    });
  }

  void _save() {
    final resolvedName = _nameController.text.trim();
    if (resolvedName.isEmpty) {
      return;
    }

    Navigator.of(context).pop(
      _GroupMetadataEditResult(
        name: resolvedName,
        description: _descriptionController.text,
        preparedAvatarPath: _preparedAvatarPath,
        removeAvatar: _removeAvatar,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final readableColors = context.backgroundReadableColors;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, bottomInset + 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: readableColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Edit Group Details',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: readableColors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Column(
                  children: [
                    GroupInfoScreenAvatarPreview(
                      group: widget.group,
                      previewBytes: _removeAvatar ? null : _previewBytes,
                      showCurrentAvatar: !_removeAvatar,
                    ),
                    const SizedBox(height: 12),
                    FilledButton.tonalIcon(
                      key: const ValueKey('group-edit-pick-photo'),
                      onPressed: _isPickingImage ? null : _pickAvatar,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: Text(
                        _preparedAvatarPath != null ||
                                widget.group.avatarPath != null
                            ? 'Change Photo'
                            : 'Add Photo',
                      ),
                    ),
                    if (_hasCurrentAvatar || _removeAvatar)
                      TextButton(
                        key: const ValueKey('group-edit-remove-photo'),
                        onPressed: _removePhoto,
                        child: const Text('Remove Photo'),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Group Name',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: readableColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              _EditorField(
                key: const ValueKey('group-edit-name-field'),
                controller: _nameController,
                maxLines: 1,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              Text(
                'Description',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: readableColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              _EditorField(
                key: const ValueKey('group-edit-description-field'),
                controller: _descriptionController,
                maxLines: 4,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: const ValueKey('group-edit-cancel'),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      key: const ValueKey('group-edit-save'),
                      onPressed: _nameController.text.trim().isEmpty
                          ? null
                          : _save,
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class GroupInfoScreenAvatarPreview extends StatelessWidget {
  final GroupModel group;
  final Uint8List? previewBytes;
  final bool showCurrentAvatar;

  const GroupInfoScreenAvatarPreview({
    super.key,
    required this.group,
    required this.previewBytes,
    required this.showCurrentAvatar,
  });

  @override
  Widget build(BuildContext context) {
    return GroupAvatar(
      groupId: group.id,
      name: group.name,
      avatarPath: previewBytes == null && showCurrentAvatar
          ? group.avatarPath
          : null,
      avatarBytes: previewBytes,
      size: 88,
      borderRadius: const BorderRadius.all(Radius.circular(28)),
      cacheBustKey:
          '${group.lastMetadataEventAt?.toIso8601String() ?? 'none'}-editor',
    );
  }
}

class _EditorField extends StatelessWidget {
  final TextEditingController controller;
  final int maxLines;
  final ValueChanged<String>? onChanged;

  const _EditorField({
    super.key,
    required this.controller,
    required this.maxLines,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: readableColors.inputFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: readableColors.inputBorder, width: 0.5),
      ),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        onChanged: onChanged,
        style: TextStyle(fontSize: 15, color: readableColors.textPrimary),
        decoration: InputDecoration(
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(14),
          hintStyle: TextStyle(color: readableColors.placeholderText),
        ),
      ),
    );
  }
}
