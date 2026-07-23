import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_picker.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/groups/application/change_group_member_role_and_broadcast_use_case.dart';
import 'package:flutter_app/features/groups/application/delete_self_removed_group_shell_use_case.dart';
import 'package:flutter_app/features/groups/application/group_avatar_storage.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/group_exit_policy.dart';
import 'package:flutter_app/features/groups/application/group_exit_intent_coordinator.dart';
import 'package:flutter_app/features/groups/application/group_exit_intent_sink.dart';
import 'package:flutter_app/features/groups/application/group_exit_terminal_diagnostics.dart';
import 'package:flutter_app/features/groups/application/group_pending_broadcast_sink.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_broadcast.dart';
import 'package:flutter_app/features/groups/application/dissolve_group_use_case.dart';
import 'package:flutter_app/features/groups/application/group_dissolve_preflight_sink.dart';
import 'package:flutter_app/features/groups/application/delete_group_and_messages_use_case.dart';
import 'package:flutter_app/features/groups/application/group_media_allowed_peers.dart';
import 'package:flutter_app/features/groups/application/group_membership_effect_authority.dart';
import 'package:flutter_app/features/groups/application/group_membership_update_listener.dart';
import 'package:flutter_app/features/groups/application/group_membership_timeline_message.dart';
import 'package:flutter_app/features/groups/application/group_membership_event_watermark.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/application/group_recovery_gate.dart';
import 'package:flutter_app/features/groups/application/group_sender_device_binding.dart';
import 'package:flutter_app/features/groups/application/group_shared_media_navigation.dart';
import 'package:flutter_app/features/groups/application/leave_group_use_case.dart';
import 'package:flutter_app/features/groups/application/refresh_pending_group_invites_for_metadata_change_use_case.dart';
import 'package:flutter_app/features/groups/application/remove_group_member_use_case.dart';
import 'package:flutter_app/features/groups/application/resend_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/application/revoke_pending_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/application/rotate_and_distribute_group_key_use_case.dart';
import 'package:flutter_app/features/groups/application/set_group_muted_use_case.dart';
import 'package:flutter_app/features/groups/application/self_removed_group_lifecycle_guard.dart';
import 'package:flutter_app/features/groups/application/signed_group_transition_audit.dart';
import 'package:flutter_app/features/groups/application/update_group_metadata_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_delivery_attempt.dart';
import 'package:flutter_app/features/groups/domain/models/group_exit_diagnostic.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/core/config/multi_device_sync_flag.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_safety_number.dart';
import 'package:flutter_app/features/groups/application/group_member_device_safety.dart';
import 'package:flutter_app/features/groups/application/manage_pending_sibling_device.dart';
import 'package:flutter_app/features/groups/domain/models/group_member_identity_safety.dart';
import 'package:flutter_app/features/groups/domain/models/pending_sibling_device.dart';
import 'package:flutter_app/features/groups/domain/repositories/pending_sibling_device_repository.dart';
import 'package:flutter_app/features/groups/presentation/widgets/pending_sibling_device_prompt.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/groups/presentation/group_invite_status_presentation.dart';
import 'package:flutter_app/features/groups/presentation/group_exit_diagnostic_presenter.dart';
import 'package:flutter_app/features/groups/presentation/group_security_status_view_state.dart';
import 'package:flutter_app/features/groups/presentation/screens/contact_picker_wired.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_info_screen.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_shared_media_library_screen.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_avatar.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_exit_recovery_sheet.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/settings/application/helpers/avatar_normalization_helper.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

class _GroupInfoAvatarUploadPhase {
  const _GroupInfoAvatarUploadPhase({required this.authority, this.uploaded});

  final GroupMembershipEffectAuthority authority;
  final GroupAvatarUpload? uploaded;
}

bool _sameGroupMetadataSnapshot(GroupModel left, GroupModel right) {
  bool sameInstant(DateTime? a, DateTime? b) {
    if (a == null || b == null) return a == null && b == null;
    return a.toUtc().isAtSameMomentAs(b.toUtc());
  }

  return left.id == right.id &&
      left.name == right.name &&
      left.description == right.description &&
      left.avatarBlobId == right.avatarBlobId &&
      left.avatarMime == right.avatarMime &&
      left.avatarPath == right.avatarPath &&
      sameInstant(left.lastMetadataEventAt, right.lastMetadataEventAt);
}

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
  final DeleteSelfRemovedGroupShellCallback? deleteSelfRemovedGroupShell;

  /// Explicit fixture-only override. Production resolves through the installed
  /// diagnosing action adapter.
  final ResolveGroupExitActionSnapshot? resolveGroupExitSnapshotForTest;
  final ImageProcessor? imageProcessor;
  final MediaPicker? mediaPicker;
  final UploadGroupAvatarFn uploadGroupAvatarFn;
  final BackgroundPreference backgroundPreference;
  final Widget Function(BuildContext context, GroupModel group)?
  sharedMediaRouteBuilder;

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
    this.deleteSelfRemovedGroupShell,
    this.resolveGroupExitSnapshotForTest,
    this.imageProcessor,
    this.mediaPicker,
    this.uploadGroupAvatarFn = uploadGroupAvatar,
    this.backgroundPreference = BackgroundPreference.defaultBackground,
    this.sharedMediaRouteBuilder,
  });

  @override
  State<GroupInfoWired> createState() => _GroupInfoWiredState();
}

class _GroupInfoWiredState extends State<GroupInfoWired> {
  static final MediaPicker _defaultMediaPicker = SystemMediaPicker();

  late GroupModel _group;
  List<GroupMember> _members = [];
  Map<String, GroupInviteDeliveryStatus> _inviteStatusesByPeerId = {};
  Map<String, GroupInviteDeliveryAttempt> _inviteAttemptsByPeerId = {};
  final Set<String> _resendingInvitePeerIds = {};
  final Set<String> _revokingInvitePeerIds = {};
  Map<String, GroupMemberIdentitySafety> _memberSafetyByPeerId = {};
  GroupSecurityStatusViewState? _securityStatus;
  List<PendingSiblingDeviceView> _pendingSiblingDeviceViews = const [];
  String? _ownPeerId;
  bool _didMutateGroup = false;
  bool _isUpdatingMute = false;
  bool _isDissolving = false;
  bool _isDeletingLocally = false;
  bool _isDeletingSelfRemovedShell = false;

  MediaPicker get _mediaPicker => widget.mediaPicker ?? _defaultMediaPicker;

  String? get _currentSenderDeviceId {
    final peerId = widget.p2pService.currentState.peerId?.trim();
    return peerId == null || peerId.isEmpty ? null : peerId;
  }

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
      final inviteDeliveryInfo = await _loadInviteDeliveryInfo(members);
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
      final pendingSiblingDeviceViews = await _loadPendingSiblingDevices(
        members,
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
        _inviteStatusesByPeerId = inviteDeliveryInfo.statusesByPeerId;
        _inviteAttemptsByPeerId = inviteDeliveryInfo.attemptsByPeerId;
        _memberSafetyByPeerId = memberSafetyByPeerId;
        _securityStatus = securityStatus;
        _pendingSiblingDeviceViews = pendingSiblingDeviceViews;
      });
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_INFO_FL_LOAD_MEMBERS_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<
    ({
      Map<String, GroupInviteDeliveryStatus> statusesByPeerId,
      Map<String, GroupInviteDeliveryAttempt> attemptsByPeerId,
    })
  >
  _loadInviteDeliveryInfo(List<GroupMember> members) async {
    final attempts =
        await widget.inviteDeliveryAttemptRepo?.getAttemptsForGroup(
          widget.group.id,
        ) ??
        const <GroupInviteDeliveryAttempt>[];
    final attemptsByPeerId = {
      for (final attempt in attempts) attempt.peerId: attempt,
    };
    final statuses = {
      for (final attempt in attempts) attempt.peerId: attempt.status,
    };

    final msgRepo = widget.msgRepo;
    if (msgRepo == null || members.isEmpty) {
      return (statusesByPeerId: statuses, attemptsByPeerId: attemptsByPeerId);
    }

    final resolvedStatuses = await Future.wait(
      members.map((member) async {
        final removedAt = await msgRepo.getLatestSystemEventTimestampForTarget(
          widget.group.id,
          eventType: 'member_removed',
          targetId: member.peerId,
        );
        final joinedAt = await _loadLatestJoinEvidenceAt(
          msgRepo,
          member,
          removedAt: removedAt,
        );
        final attempt = attemptsByPeerId[member.peerId];
        if (joinedAt != null &&
            _isCurrentJoinEvidence(
              joinedAt: joinedAt,
              removedAt: removedAt,
              attempt: attempt,
            )) {
          return MapEntry(member.peerId, GroupInviteDeliveryStatus.joined);
        }
        if (_isJoinedAttemptInvalidatedByRemoval(
          attempt: attempt,
          removedAt: removedAt,
        )) {
          return MapEntry(member.peerId, GroupInviteDeliveryStatus.unknown);
        }
        return null;
      }),
    );
    for (final entry
        in resolvedStatuses
            .whereType<MapEntry<String, GroupInviteDeliveryStatus>>()) {
      if (entry.value == GroupInviteDeliveryStatus.unknown) {
        statuses.remove(entry.key);
      } else {
        statuses[entry.key] = entry.value;
      }
    }
    return (statusesByPeerId: statuses, attemptsByPeerId: attemptsByPeerId);
  }

  Future<DateTime?> _loadLatestJoinEvidenceAt(
    GroupMessageRepository msgRepo,
    GroupMember member, {
    DateTime? removedAt,
  }) async {
    // A member_joined receipt FROM THE MEMBER is the only proof of a genuine
    // join — the admin observes it after the member rejoins and obtains the key.
    final memberConfirmedAt = await msgRepo
        .getLatestSystemEventTimestampForTarget(
          widget.group.id,
          eventType: 'member_joined',
          targetId: member.peerId,
        );
    // B3.1: admin-authored add events (member_added / members_added) are NOT a
    // join confirmation by themselves. After a removal, the admin's OWN re-add
    // must not mark the member "joined" until a real member_joined receipt
    // arrives (otherwise a re-added member shows "joined" before they actually
    // rejoin and obtain the new key). Before any removal, the admin add is the
    // best first-join evidence we have, so it still counts.
    if (removedAt != null) {
      return memberConfirmedAt;
    }
    final adminAddTimestamps = await Future.wait([
      msgRepo.getLatestSystemEventTimestampForTarget(
        widget.group.id,
        eventType: 'member_added',
        targetId: member.peerId,
      ),
      msgRepo.getLatestSystemEventTimestampForTarget(
        widget.group.id,
        eventType: 'members_added',
        targetId: member.peerId,
      ),
    ]);
    return _latestTimestamp([memberConfirmedAt, ...adminAddTimestamps]);
  }

  DateTime? _latestTimestamp(Iterable<DateTime?> values) {
    DateTime? latest;
    for (final value in values) {
      if (value == null) {
        continue;
      }
      final normalized = value.toUtc();
      if (latest == null || normalized.isAfter(latest)) {
        latest = normalized;
      }
    }
    return latest;
  }

  bool _isCurrentJoinEvidence({
    required DateTime joinedAt,
    DateTime? removedAt,
    GroupInviteDeliveryAttempt? attempt,
  }) {
    final normalizedJoinedAt = joinedAt.toUtc();
    if (removedAt != null && !normalizedJoinedAt.isAfter(removedAt.toUtc())) {
      return false;
    }
    if (attempt == null || attempt.status == GroupInviteDeliveryStatus.joined) {
      return true;
    }
    return !normalizedJoinedAt.isBefore(attempt.attemptedAt.toUtc());
  }

  bool _isJoinedAttemptInvalidatedByRemoval({
    GroupInviteDeliveryAttempt? attempt,
    DateTime? removedAt,
  }) {
    if (attempt == null ||
        attempt.status != GroupInviteDeliveryStatus.joined ||
        removedAt == null) {
      return false;
    }
    return removedAt.toUtc().isAfter(attempt.updatedAt.toUtc());
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
        final safety = await resolveGroupMemberDeviceSafety(
          member: member,
          savedContact: contact,
          snapshotRepo: asGroupMemberDeviceSnapshotRepository(widget.groupRepo),
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

  // R2: pending sibling devices awaiting an explicit user trust decision.
  Future<List<PendingSiblingDeviceView>> _loadPendingSiblingDevices(
    List<GroupMember> members,
  ) async {
    if (!kMultiDeviceSyncEnabled) {
      return const [];
    }
    final repo = widget.groupRepo;
    if (repo is! PendingSiblingDeviceRepository) {
      return const [];
    }
    try {
      final pending = await (repo as PendingSiblingDeviceRepository)
          .getPendingSiblingDevicesForGroup(widget.group.id);
      return pending.map((device) {
        final member = members
            .where((m) => m.peerId == device.memberPeerId)
            .cast<GroupMember?>()
            .firstWhere((m) => m != null, orElse: () => null);
        final fingerprint =
            '${device.deviceSigningPublicKey}:'
            '${device.mlKemPublicKey ?? ''}:'
            '${device.keyPackageId ?? ''}';
        final safetyNumber = ContactSafetyNumber.build(
          peerId: device.memberPeerId,
          publicKey: device.verifiedAccountSigningPublicKey,
          mlKemPublicKey: device.mlKemPublicKey,
          deviceFingerprints: [fingerprint],
        );
        return PendingSiblingDeviceView(
          device: device,
          memberLabel: member?.username ?? device.memberPeerId,
          safetyNumber: safetyNumber,
        );
      }).toList();
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_INFO_FL_PENDING_SIBLING_LOAD_ERROR',
        details: {'error': e.toString()},
      );
      return const [];
    }
  }

  Future<void> _onVerifyPendingSiblingDevice(
    PendingSiblingDevice device,
  ) async {
    final repo = widget.groupRepo;
    if (repo is! PendingSiblingDeviceRepository) return;
    await verifyAndAdmitPendingSiblingDevice(
      pendingRepo: repo as PendingSiblingDeviceRepository,
      groupRepo: widget.groupRepo,
      pending: device,
    );
    await _loadGroupInfo();
  }

  Future<void> _onRejectPendingSiblingDevice(
    PendingSiblingDevice device,
  ) async {
    final repo = widget.groupRepo;
    if (repo is! PendingSiblingDeviceRepository) return;
    await rejectPendingSiblingDevice(
      pendingRepo: repo as PendingSiblingDeviceRepository,
      groupRepo: widget.groupRepo,
      pending: device,
    );
    await _loadGroupInfo();
  }

  Future<void> _onLeave() async {
    GroupExitSnapshot? snapshot;
    try {
      final fixtureResolve = widget.resolveGroupExitSnapshotForTest;
      snapshot = fixtureResolve == null
          ? await resolveGroupExitActionSnapshot(_group.id)
          : await fixtureResolve(_group.id);
    } catch (_) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_INFO_FL_EXIT_CLASSIFY_ERROR',
        details: const {
          'code': 'EX01',
          'phase': 'authority',
          'severity': 'failure',
        },
      );
    }
    if (!mounted) return;

    if (snapshot == null) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _group.selfRemovedAt != null
                ? l10n.group_removed_delete_failed
                : l10n.group_info_leave_failed,
          ),
        ),
      );
      return;
    }
    if (snapshot.group == null) {
      _didMutateGroup = true;
      Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }
    if (snapshot.disposition == GroupExitDisposition.selfRemovedDeleteLocally) {
      await _confirmDeleteSelfRemovedGroupShell(groupId: _group.id);
      return;
    }
    if (snapshot.disposition == GroupExitDisposition.noOp) {
      await _loadGroupInfo();
      return;
    }

    final result = await requestGroupExitIntentLeave(_group.id);
    await _handleGroupExitIntentResult(result);
  }

  Future<void> _handleGroupExitIntentResult(
    GroupExitIntentRequestResult result,
  ) async {
    if (!mounted) return;
    switch (result.status) {
      case GroupExitIntentRequestStatus.started:
      case GroupExitIntentRequestStatus.noOp:
        _didMutateGroup = true;
        Navigator.of(context).popUntil((route) => route.isFirst);
        return;
      case GroupExitIntentRequestStatus.pendingRoleSync:
        await _showPendingRoleSyncExit(result);
        return;
      case GroupExitIntentRequestStatus.queued:
        await _showQueuedExit(result);
        return;
      case GroupExitIntentRequestStatus.blockedLastAdmin:
        if (result.intent != null) {
          await _showQueuedExit(result);
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(lastAdminLeaveBlockedMessage)),
        );
        return;
      case GroupExitIntentRequestStatus.unavailable:
        if (result.intent != null) {
          await _showQueuedExit(result);
          return;
        }
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_INFO_FL_LEAVE_ERROR',
          details: const {
            'code': 'EX01',
            'phase': 'authority',
            'severity': 'failure',
          },
        );
        await _loadGroupInfo();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_presentExitResultFailure(result))),
        );
        return;
      case GroupExitIntentRequestStatus.failed:
        if (result.intent != null) {
          await _showQueuedExit(result);
          return;
        }
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_INFO_FL_LEAVE_ERROR',
          details: const {
            'code': 'EX99',
            'phase': 'authority',
            'severity': 'failure',
          },
        );
        await _loadGroupInfo();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_presentExitResultFailure(result))),
        );
        return;
    }
  }

  Future<bool> _closeSheetForExitResult(
    GroupExitIntentRequestResult result,
  ) async {
    if (!mounted) return false;
    switch (result.status) {
      case GroupExitIntentRequestStatus.started:
      case GroupExitIntentRequestStatus.queued:
      case GroupExitIntentRequestStatus.noOp:
        return true;
      case GroupExitIntentRequestStatus.pendingRoleSync:
        return false;
      case GroupExitIntentRequestStatus.blockedLastAdmin:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(lastAdminLeaveBlockedMessage)),
        );
        return false;
      case GroupExitIntentRequestStatus.unavailable:
      case GroupExitIntentRequestStatus.failed:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_presentExitResultFailure(result))),
        );
        return false;
    }
  }

  String _presentExitResultFailure(GroupExitIntentRequestResult result) {
    final l10n = AppLocalizations.of(context)!;
    final code = primaryGroupExitPublicCode(result.diagnosticFacts);
    return code == null
        ? l10n.group_info_leave_failed
        : presentGroupExitDiagnostic(
            l10n,
            code,
            leading: l10n.group_info_leave_failed,
          );
  }

  Future<void> _showPendingRoleSyncExit(
    GroupExitIntentRequestResult initialResult,
  ) async {
    var navigateAfterClose = false;
    var currentIntentId = initialResult.intent?.intentId;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => GroupExitRecoverySheet.pendingRoleSync(
        groupName: _group.name,
        diagnosticGroupId: _group.id,
        diagnosticIntentId: currentIntentId,
        diagnosticActionRef: () => currentIntentId == null
            ? null
            : (groupId: _group.id, intentId: currentIntentId!),
        initialDiagnosticCode: primaryGroupExitPublicCode(
          initialResult.diagnosticFacts,
        ),
        onLeaveWhenSyncCompletes: () async {
          final result = await queueGroupExitIntentLeaveWhenSyncCompletes(
            _group.id,
          );
          currentIntentId = result.intent?.intentId ?? currentIntentId;
          navigateAfterClose = await _closeSheetForExitResult(result);
          return navigateAfterClose;
        },
        onTryAgain: () async {
          final result = await retryGroupExitIntentLeave(_group.id);
          currentIntentId = result.intent?.intentId ?? currentIntentId;
          navigateAfterClose = await _closeSheetForExitResult(result);
          return navigateAfterClose;
        },
      ),
    );
    if (!mounted) return;
    if (navigateAfterClose) {
      _didMutateGroup = true;
      Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }
    await _loadGroupInfo();
  }

  Future<void> _showQueuedExit(
    GroupExitIntentRequestResult initialResult,
  ) async {
    var navigateAfterClose = false;
    var currentIntentId = initialResult.intent?.intentId;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => GroupExitRecoverySheet.queuedLeave(
        groupName: _group.name,
        diagnosticGroupId: _group.id,
        diagnosticIntentId: currentIntentId,
        diagnosticActionRef: () => currentIntentId == null
            ? null
            : (groupId: _group.id, intentId: currentIntentId!),
        initialDiagnosticCode: primaryGroupExitPublicCode(
          initialResult.diagnosticFacts,
        ),
        onTryAgain: () async {
          final result = await retryGroupExitIntentLeave(_group.id);
          currentIntentId = result.intent?.intentId ?? currentIntentId;
          navigateAfterClose = await _closeSheetForExitResult(result);
          return navigateAfterClose;
        },
        onCancelQueuedLeave: () async {
          final result = await cancelQueuedGroupExitIntent(_group.id);
          return switch (result.status) {
            GroupExitIntentCancelStatus.cancelled ||
            GroupExitIntentCancelStatus.notFound =>
              GroupExitQueuedCancelUiResult.cancelled,
            GroupExitIntentCancelStatus.tooLate =>
              GroupExitQueuedCancelUiResult.tooLate,
            GroupExitIntentCancelStatus.unavailable ||
            GroupExitIntentCancelStatus.failed =>
              GroupExitQueuedCancelUiResult.failed,
          };
        },
        onRefreshQueuedState: _loadGroupInfo,
      ),
    );
    if (!mounted) return;
    if (navigateAfterClose) {
      _didMutateGroup = true;
      Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }
    await _loadGroupInfo();
  }

  Future<void> _confirmDeleteSelfRemovedGroupShell({
    required String groupId,
  }) async {
    if (!mounted || _isDeletingSelfRemovedShell) return;
    _isDeletingSelfRemovedShell = true;
    final l10n = AppLocalizations.of(context)!;
    try {
      final shouldDelete = await showDialog<bool>(
        context: context,
        builder: (context) {
          final dialogL10n = AppLocalizations.of(context)!;
          return AlertDialog(
            title: Text(dialogL10n.group_removed_delete_title),
            content: Text(dialogL10n.group_removed_delete_body),
            actions: [
              TextButton(
                key: const ValueKey('group-self-removed-delete-cancel'),
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(dialogL10n.btn_cancel),
              ),
              FilledButton(
                key: const ValueKey('group-self-removed-delete-confirm'),
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(dialogL10n.group_removed_delete_action),
              ),
            ],
          );
        },
      );
      if (shouldDelete != true || !mounted) return;

      DeleteSelfRemovedGroupShellActionObservation observation;
      try {
        observation = await runDeleteSelfRemovedGroupShellPresentationAction(
          groupId: groupId,
          identityRepository: widget.identityRepo,
          legacyTestCallback: widget.deleteSelfRemovedGroupShell,
        );
      } catch (_) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_INFO_FL_DELETE_SELF_REMOVED_GROUP_ERROR',
          details: const {
            'code': 'EX10',
            'phase': 'local_delete',
            'severity': 'failure',
          },
        );
        observation = const DeleteSelfRemovedGroupShellActionObservation(
          result: DeleteSelfRemovedGroupShellResult.cleanupIncomplete,
          publicCode: GroupExitDiagnosticPublicCode.ex10,
        );
      }
      if (!mounted) return;

      switch (observation.result) {
        case DeleteSelfRemovedGroupShellResult.deleted:
        case DeleteSelfRemovedGroupShellResult.alreadyAbsent:
          _didMutateGroup = true;
          Navigator.of(context).popUntil((route) => route.isFirst);
          return;
        case DeleteSelfRemovedGroupShellResult.refusedStateChanged:
          await _loadGroupInfo();
          return;
        case DeleteSelfRemovedGroupShellResult.cleanupIncomplete:
          await _loadGroupInfo();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  observation.publicCode == null
                      ? l10n.group_removed_delete_failed
                      : presentGroupExitDiagnostic(
                          l10n,
                          observation.publicCode!,
                          leading: l10n.group_removed_delete_failed,
                        ),
                ),
              ),
            );
          }
          return;
      }
    } finally {
      _isDeletingSelfRemovedShell = false;
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
      // 154: the switch + bell icon + description already flip above, so the
      // success snackbar was redundant. Confirm with a tactile selectionClick
      // and reserve the snackbar channel for the failure path below.
      HapticFeedback.selectionClick();
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.group_info_mute_update_failed,
          ),
        ),
      );
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
      builder: (context) {
        final l10n = AppLocalizations.of(context)!;
        return AlertDialog(
          title: Text(l10n.group_info_dissolve_title),
          content: Text(l10n.group_info_dissolve_body),
          actions: [
            TextButton(
              key: const ValueKey('group-dissolve-cancel'),
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.btn_cancel),
            ),
            FilledButton(
              key: const ValueKey('group-dissolve-confirm'),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.group_info_dissolve_action),
            ),
          ],
        );
      },
    );

    if (shouldDissolve == true) {
      await _onDissolveGroup();
    }
  }

  Future<void> _onDissolveGroup() async {
    if (_isDissolving || widget.msgRepo == null) {
      return;
    }

    // Capture localized copy before awaits, when this State is known mounted.
    final noIdentityError = AppLocalizations.of(
      context,
    )!.group_info_no_identity;
    setState(() => _isDissolving = true);

    try {
      final identity = await widget.identityRepo.loadIdentity();
      if (identity == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(noIdentityError)));
        return;
      }

      // Sign the dissolve audit with the same device/transport binding the
      // receiver observes live (Go-stamped), so verifyGroupTransitionAudit on
      // every member matches signed-vs-observed and applies isDissolved. Without
      // this the signer omits the binding and receivers reject the dissolve
      // (device_mismatch/transport_mismatch), leaving the group live for all but
      // the dissolver. Mirrors the member_removed/members_added sibling flows.
      final senderBinding = await resolveGroupSenderDeviceBinding(
        groupRepo: widget.groupRepo,
        groupId: _group.id,
        senderPeerId: identity.peerId,
        preferredDeviceId: _currentSenderDeviceId,
        preferredTransportPeerId: _currentSenderDeviceId,
        senderPublicKey: identity.publicKey,
      );

      final (result, transitionGroup) = await dissolveGroup(
        bridge: widget.bridge,
        groupRepo: widget.groupRepo,
        msgRepo: widget.msgRepo!,
        preflightAuthority: requireGroupDissolvePreflightAuthority(),
        groupId: _group.id,
        actorPeerId: identity.peerId,
        actorUsername: identity.username,
        actorPublicKey: identity.publicKey,
        actorPrivateKey: identity.privateKey,
        actorDeviceId: senderBinding.deviceId,
        actorTransportPeerId: senderBinding.transportPeerId,
        actorKeyPackageId: senderBinding.keyPackageId,
      );

      switch (result) {
        case DissolveGroupResult.success:
          _didMutateGroup = true;
          await _loadGroupInfo();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.group_dissolved),
            ),
          );
          break;
        case DissolveGroupResult.bridgeError:
          final committed = transitionGroup?.isDissolved == true;
          if (committed) _didMutateGroup = true;
          await _loadGroupInfo();
          if (!mounted) return;
          final l10n = AppLocalizations.of(context)!;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                committed
                    ? l10n.group_info_dissolved_recovery
                    : l10n.group_info_dissolve_failed,
              ),
            ),
          );
          break;
        case DissolveGroupResult.alreadyDissolved:
          _didMutateGroup = true;
          await _loadGroupInfo();
          if (!mounted) return;
          final l10n = AppLocalizations.of(context)!;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.group_info_already_dissolved)),
          );
          break;
        case DissolveGroupResult.unauthorized:
          if (!mounted) return;
          final l10n = AppLocalizations.of(context)!;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.group_info_admins_only_dissolve)),
          );
          break;
        case DissolveGroupResult.notFound:
          if (!mounted) return;
          final l10n = AppLocalizations.of(context)!;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(l10n.group_info_not_found)));
          break;
        case DissolveGroupResult.exitWorkPending:
          if (!mounted) return;
          final l10n = AppLocalizations.of(context)!;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.group_info_dissolve_failed)),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.group_info_dissolve_failed,
          ),
        ),
      );
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
      builder: (context) {
        final l10n = AppLocalizations.of(context)!;
        return AlertDialog(
          title: Text(l10n.group_info_delete_local_title),
          content: Text(l10n.group_info_delete_local_body),
          actions: [
            TextButton(
              key: const ValueKey('group-delete-local-cancel'),
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.btn_cancel),
            ),
            FilledButton(
              key: const ValueKey('group-delete-local-confirm'),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.group_info_delete_local_action),
            ),
          ],
        );
      },
    );

    if (shouldDelete == true) {
      await _onDeleteGroupLocally();
    }
  }

  Future<void> _onDeleteGroupLocally() async {
    if (_isDeletingLocally) {
      return;
    }

    setState(() => _isDeletingLocally = true);

    try {
      final observation = await runDeleteDissolvedGroupShellPresentationAction(
        groupId: _group.id,
        legacyTestCallback: widget.msgRepo == null
            ? null
            : (groupId) => deleteGroupAndMessages(
                bridge: widget.bridge,
                groupRepo: widget.groupRepo,
                groupMessageRepo: widget.msgRepo!,
                groupId: groupId,
                deleteLocallyIfDissolved: true,
              ),
      );

      if (observation.status ==
          DeleteDissolvedGroupShellActionStatus.authorityUnavailable) {
        if (!mounted) return;
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              presentGroupExitDiagnostic(
                l10n,
                observation.publicCode ?? GroupExitDiagnosticPublicCode.ex01,
                leading: l10n.group_info_delete_local_failed,
              ),
            ),
          ),
        );
        return;
      }

      _didMutateGroup = true;
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on DissolvedGroupDeleteStateChangedException {
      if (!mounted) return;
      final message = AppLocalizations.of(
        context,
      )!.group_info_delete_local_failed;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_INFO_FL_DELETE_LOCAL_DISSOLVED_ERROR',
        details: const {
          'code': 'EX10',
          'phase': 'local_delete',
          'severity': 'failure',
        },
      );
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            presentGroupExitDiagnostic(
              l10n,
              GroupExitDiagnosticPublicCode.ex10,
              leading: l10n.group_info_delete_local_failed,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isDeletingLocally = false);
      } else {
        _isDeletingLocally = false;
      }
    }
  }

  Future<void> _rollbackFailedMemberRemoval({
    required GroupModel preRemovalGroup,
    required GroupMember removedMember,
    required String? removalTimelineMessageId,
  }) async {
    final existingMember = await widget.groupRepo.getMember(
      preRemovalGroup.id,
      removedMember.peerId,
    );
    if (existingMember == null) {
      await widget.groupRepo.saveMember(removedMember);
    }

    final currentGroup = await widget.groupRepo.getGroup(preRemovalGroup.id);
    final restoredGroup = (currentGroup ?? preRemovalGroup).copyWith(
      lastMembershipEventAt: preRemovalGroup.lastMembershipEventAt,
    );
    if (currentGroup != null) {
      await widget.groupRepo.updateGroup(restoredGroup);
    }

    if (removalTimelineMessageId != null) {
      await widget.msgRepo?.deleteMessage(removalTimelineMessageId);
    }

    final restoredMembers = await widget.groupRepo.getMembers(
      preRemovalGroup.id,
    );
    await callGroupUpdateConfig(
      widget.bridge,
      groupId: preRemovalGroup.id,
      groupConfig: buildGroupConfigPayload(restoredGroup, restoredMembers),
    );

    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INFO_FL_REMOVE_MEMBER_ROLLBACK_RESTORED',
      details: {
        'groupId': preRemovalGroup.id.length > 8
            ? preRemovalGroup.id.substring(0, 8)
            : preRemovalGroup.id,
        'memberPeerId': removedMember.peerId.length > 10
            ? removedMember.peerId.substring(0, 10)
            : removedMember.peerId,
      },
    );
  }

  Future<void> _onRemoveMember(GroupMember member) async {
    // Captured pre-gap: used after awaits, when this State may be unmounted.
    final publishRemovalFailedError = AppLocalizations.of(
      context,
    )!.group_info_publish_member_removal_failed;
    GroupModel? preRemovalGroup;
    GroupMember? preRemovalMember;
    String? removalTimelineMessageId;
    var localRemovalAccepted = false;
    // Once the member_removed broadcast is committed, a later failure must NOT
    // roll back / re-add the member (re-granting the key violates INV-R2).
    var removalBroadcast = false;

    try {
      final identity = await widget.identityRepo.loadIdentity();
      preRemovalGroup = await widget.groupRepo.getGroup(widget.group.id);
      preRemovalMember = await widget.groupRepo.getMember(
        widget.group.id,
        member.peerId,
      );
      final preTransitionStateHash = await buildGroupTransitionStateHash(
        widget.groupRepo,
        widget.group.id,
      );

      // 1. Remove from DB + update admin's Go config. Pass NO explicit eventAt:
      // like the role toggle, the use case mints the canonical (eventAt,
      // eventId) pair monotonically from the wall clock — lifted past a
      // skew-advanced watermark so this legitimate local removal can never
      // self-block as "stale" — and returns it. The broadcast + timeline below
      // publish the SAME pair so a concurrent removal tie-breaks against one id
      // on every device (G5), and the wired timeline row dedups against the one
      // the use case already persisted under the normalized instant.
      final minted = await removeGroupMember(
        bridge: widget.bridge,
        groupRepo: widget.groupRepo,
        groupId: widget.group.id,
        memberPeerId: member.peerId,
        selfPeerId: identity?.peerId,
        actorUsername: identity?.username,
        msgRepo: widget.msgRepo,
      );
      localRemovalAccepted = true;
      final eventAt = minted.eventAt;
      final sourceEventId = minted.eventId;
      if (identity != null) {
        removalTimelineMessageId = buildMemberRemovedTimelineMessage(
          groupId: widget.group.id,
          removedPeerId: member.peerId,
          removedUsername: member.username,
          senderId: identity.peerId,
          senderUsername: identity.username,
          eventAt: eventAt,
        ).id;
      }

      // 2. Broadcast member_removed system message to remaining members
      if (identity != null) {
        final group = await widget.groupRepo.getGroup(widget.group.id);
        final allMembers = await widget.groupRepo.getMembers(widget.group.id);

        if (group != null) {
          final groupConfig = buildGroupConfigPayload(group, allMembers);
          final senderBinding = await resolveGroupSenderDeviceBinding(
            groupRepo: widget.groupRepo,
            groupId: widget.group.id,
            senderPeerId: identity.peerId,
            preferredDeviceId: _currentSenderDeviceId,
            preferredTransportPeerId: _currentSenderDeviceId,
            senderPublicKey: identity.publicKey,
          );
          final removalReplayRecipientPeerIds = <String>{
            member.peerId,
            ...allMembers
                .map((remainingMember) => remainingMember.peerId)
                .where(
                  (peerId) => peerId.isNotEmpty && peerId != identity.peerId,
                ),
          }.toList(growable: false);

          final sysPayload = await signGroupSystemTransitionPayload(
            bridge: widget.bridge,
            groupRepo: widget.groupRepo,
            groupId: widget.group.id,
            transitionType: 'member_removed',
            sourceEventId: sourceEventId,
            eventAt: eventAt,
            actorPeerId: identity.peerId,
            actorUsername: identity.username,
            actorSigningPublicKey: identity.publicKey,
            actorPrivateKey: identity.privateKey,
            actorDeviceId: senderBinding.deviceId,
            actorTransportPeerId: senderBinding.transportPeerId,
            actorKeyPackageId: senderBinding.keyPackageId,
            preTransitionStateHash: preTransitionStateHash,
            systemPayload: {
              '__sys': 'member_removed',
              'member': {'peerId': member.peerId, 'username': member.username},
              'removedAt': eventAt.toIso8601String(),
              'groupConfig': groupConfig,
            },
          );
          final sysMessage = jsonEncode(sysPayload);
          final removalTimelineMessage = buildMemberRemovedTimelineMessage(
            groupId: widget.group.id,
            removedPeerId: member.peerId,
            removedUsername: member.username,
            senderId: identity.peerId,
            senderUsername: identity.username,
            eventAt: eventAt,
          );
          if (widget.msgRepo != null) {
            await widget.msgRepo!.saveMessage(removalTimelineMessage);
          }
          final removalInboxPayload = jsonEncode({
            'groupId': widget.group.id,
            'senderId': identity.peerId,
            'senderUsername': identity.username,
            if (senderBinding.deviceId != null)
              'senderDeviceId': senderBinding.deviceId,
            if (senderBinding.transportPeerId != null)
              'transportPeerId': senderBinding.transportPeerId,
            'text': sysMessage,
            'timestamp': eventAt.toIso8601String(),
            'messageId': sourceEventId,
          });

          final publishResult = await callGroupPublish(
            widget.bridge,
            groupId: widget.group.id,
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
            // Soft publish failure (e.g. BRIDGE_TIMEOUT / no fanout): the
            // removal is already committed locally and must stand. Rather than
            // rolling the member back (which would re-grant the rotated-away
            // key — INV-R2) or reporting a false success, durably enqueue the
            // already-signed member_removed broadcast for re-push on the next
            // rejoin/foreground (G3), then fall through to the inbox store + key
            // rotation so the removal still converges. Re-uses the original
            // (eventAt, sourceEventId) so a retry can't resurrect stale state.
            // Falls back to the hard throw only when no durable sink is wired.
            if (hasGroupPendingBroadcastEnqueueSink) {
              final nowUtc = DateTime.now().toUtc();
              await enqueueGroupPendingBroadcast(
                GroupPendingBroadcast(
                  id: 'pending_group_broadcast:${widget.group.id}:$sourceEventId',
                  groupId: widget.group.id,
                  kind: 'member_removed',
                  sysText: sysMessage,
                  recipientPeerIds: removalReplayRecipientPeerIds,
                  eventAt: eventAt,
                  sourceMessageId: sourceEventId,
                  createdAt: nowUtc,
                  updatedAt: nowUtc,
                ),
              );
              emitFlowEvent(
                layer: 'FL',
                event: 'GROUP_INFO_FL_REMOVE_BROADCAST_QUEUED',
                details: {
                  'groupId': widget.group.id.length > 8
                      ? widget.group.id.substring(0, 8)
                      : widget.group.id,
                },
              );
            } else {
              final errorMessage = publishResult['errorMessage']?.toString();
              throw StateError(
                errorMessage != null && errorMessage.isNotEmpty
                    ? errorMessage
                    : publishRemovalFailedError,
              );
            }
          }
          // member_removed is published (or durably enqueued for re-push): the
          // removal is committed group-wide. From here, failures are surfaced
          // as warnings, never rolled back.
          removalBroadcast = true;
          final removalReplayEnvelope = await buildGroupOfflineReplayEnvelope(
            bridge: widget.bridge,
            groupRepo: widget.groupRepo,
            groupId: widget.group.id,
            payloadType: groupOfflineReplayPayloadTypeMessage,
            plaintext: removalInboxPayload,
            senderPeerId: identity.peerId,
            senderPublicKey: identity.publicKey,
            senderPrivateKey: identity.privateKey,
            senderDeviceId: senderBinding.deviceId,
            senderTransportPeerId: senderBinding.transportPeerId,
            senderKeyPackageId: senderBinding.keyPackageId,
            messageId: removalTimelineMessage.id,
            recipientPeerIds: removalReplayRecipientPeerIds,
          );
          await callGroupInboxStore(
            widget.bridge,
            widget.group.id,
            removalReplayEnvelope,
            recipientPeerIds: removalReplayRecipientPeerIds,
            preserveRecipientPeerIds: true,
          );
          for (final target in groupMembershipUpdateDirectTargets(
            members: [member],
          )) {
            unawaited(
              sendGroupMembershipUpdateDirect(
                sendP2PMessage: (peerId, message) async {
                  return widget.p2pService.sendMessage(peerId, message);
                },
                recipientPeerId: target.deliveryPeerId,
                groupId: widget.group.id,
                senderPeerId: identity.peerId,
                replayEnvelope: removalReplayEnvelope,
                timestamp: eventAt,
                messageId: sourceEventId,
              ),
            );
          }

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
          final rotationOutcome = await rotateAndDistributeGroupKey(
            bridge: widget.bridge,
            groupRepo: widget.groupRepo,
            groupId: widget.group.id,
            selfPeerId: identity.peerId,
            senderPublicKey: identity.publicKey,
            senderPrivateKey: identity.privateKey,
            senderUsername: identity.username,
            sendP2PMessage: (peerId, message) async {
              return widget.p2pService.sendMessage(peerId, message);
            },
            storeP2PMessageInInbox: (peerId, message) async {
              return widget.p2pService.storeInInbox(peerId, message);
            },
          );
          if (!rotationOutcome.rotated) {
            // Genuine re-key failure AFTER the removal was broadcast. The
            // removal stands; do NOT throw into the re-add rollback (INV-R2).
            // The removed member keeps the OLD key until a later successful
            // rotation (forward-secrecy delayed, never re-granted). Surface a
            // retryable, non-fatal warning.
            emitFlowEvent(
              layer: 'FL',
              event: 'GROUP_INFO_FL_REMOVE_REKEY_DEFERRED',
              details: {
                'groupId': widget.group.id.length > 8
                    ? widget.group.id.substring(0, 8)
                    : widget.group.id,
                'removedPeerId': member.peerId.length > 10
                    ? member.peerId.substring(0, 10)
                    : member.peerId,
              },
            );
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    AppLocalizations.of(context)!.group_info_rotate_key_failed,
                  ),
                ),
              );
            }
          } else if (!rotationOutcome.fullyDistributed) {
            // Epoch promoted (removed member excluded) but some remaining
            // members were keyless / undelivered and are deferred. The removal
            // is durable; surface a non-fatal info notice.
            emitFlowEvent(
              layer: 'FL',
              event: 'GROUP_INFO_FL_REMOVE_PARTIAL_DISTRIBUTION',
              details: {
                'groupId': widget.group.id.length > 8
                    ? widget.group.id.substring(0, 8)
                    : widget.group.id,
                'deferredCount': rotationOutcome.deferredPeerIds.length,
              },
            );
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    AppLocalizations.of(
                      context,
                    )!.group_info_remove_member_partial_distribution,
                  ),
                ),
              );
            }
          }
        }
      }

      _didMutateGroup = true;
      await _loadGroupInfo();
    } catch (e) {
      // Roll back ONLY when the removal was never broadcast (pre-broadcast
      // failure). After the broadcast, re-adding the member would re-grant the
      // rotated-away key (INV-R2), so the catch falls through to a warning only.
      if (localRemovalAccepted &&
          !removalBroadcast &&
          preRemovalGroup != null &&
          preRemovalMember != null) {
        try {
          await _rollbackFailedMemberRemoval(
            preRemovalGroup: preRemovalGroup,
            removedMember: preRemovalMember,
            removalTimelineMessageId: removalTimelineMessageId,
          );
        } catch (rollbackError) {
          emitFlowEvent(
            layer: 'FL',
            event: 'GROUP_INFO_FL_REMOVE_MEMBER_ROLLBACK_ERROR',
            details: {
              'groupId': widget.group.id.length > 8
                  ? widget.group.id.substring(0, 8)
                  : widget.group.id,
              'error': rollbackError.toString(),
            },
          );
        }
      }
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_INFO_FL_REMOVE_MEMBER_ERROR',
        details: {'error': e.toString()},
      );
      if (!mounted) return;
      // Once the removal is broadcast it is durable (no rollback). A failure in
      // a later sync step (inbox replay, etc.) must NOT be surfaced as "failed
      // to remove" — that would imply the member is still present. Show the
      // honest "removed, some sync deferred" notice instead.
      final message = removalBroadcast
          ? AppLocalizations.of(
              context,
            )!.group_info_remove_member_partial_distribution
          : e is StateError
          ? e.message
          : AppLocalizations.of(context)!.group_info_remove_member_failed;
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
      builder: (context) {
        final l10n = AppLocalizations.of(context)!;
        return AlertDialog(
          title: Text(
            l10n.group_info_remove_member_title(
              member.username ?? l10n.group_info_member_fallback,
            ),
          ),
          content: Text(l10n.group_info_remove_member_body),
          actions: [
            TextButton(
              key: const ValueKey('group-remove-cancel'),
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.btn_cancel),
            ),
            FilledButton(
              key: const ValueKey('group-remove-confirm'),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.group_info_remove_action),
            ),
          ],
        );
      },
    );

    if (shouldRemove == true) {
      await _onRemoveMember(member);
    }
  }

  Future<void> _onToggleAdminRole(GroupMember member) async {
    final nextRole = member.role == MemberRole.admin
        ? MemberRole.writer
        : MemberRole.admin;
    final l10n = AppLocalizations.of(context)!;
    final noIdentityMessage = l10n.group_info_no_identity;

    try {
      final identity = await widget.identityRepo.loadIdentity();
      if (identity == null) {
        throw StateError(noIdentityMessage);
      }
      final result = await changeGroupMemberRoleAndBroadcast(
        bridge: widget.bridge,
        groupRepo: widget.groupRepo,
        identityRepo: widget.identityRepo,
        groupId: _group.id,
        memberPeerId: member.peerId,
        role: nextRole,
        messageRepo: widget.msgRepo,
        inviteDeliveryAttemptRepo: widget.inviteDeliveryAttemptRepo,
        senderDeviceId: _currentSenderDeviceId,
        sendP2PMessage: (peerId, message) =>
            widget.p2pService.sendMessage(peerId, message),
      );

      _didMutateGroup =
          result.outcome != ChangeGroupMemberRoleAndBroadcastOutcome.unchanged;
      await _loadGroupInfo();
      if (!mounted) return;

      if (result.outcome ==
          ChangeGroupMemberRoleAndBroadcastOutcome.pendingSync) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.group_info_member_role_update_failed)),
        );
        return;
      }
      if (result.outcome ==
          ChangeGroupMemberRoleAndBroadcastOutcome.unchanged) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.updatedMember.role == MemberRole.admin
                ? l10n.group_info_admin_added(
                    _displayName(result.updatedMember),
                  )
                : l10n.group_info_admin_removed(
                    _displayName(result.updatedMember),
                  ),
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
      // The preflight identity failure is already localized above. Other
      // StateErrors come from the shared application action and are diagnostic
      // English, so they must not leak into localized presentation copy.
      final message = e is StateError && e.message == noIdentityMessage
          ? noIdentityMessage
          : AppLocalizations.of(context)!.group_info_member_role_update_failed;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      await _loadGroupInfo();
    }
  }

  Future<void> _confirmRoleChange(GroupMember member) async {
    if (!mounted) return;

    final isPromoting = member.role != MemberRole.admin;

    final shouldChangeRole = await showDialog<bool>(
      context: context,
      builder: (context) {
        final l10n = AppLocalizations.of(context)!;
        final name = _displayName(member);
        return AlertDialog(
          title: Text(
            isPromoting
                ? l10n.group_info_make_admin_title(name)
                : l10n.group_info_remove_admin_title(name),
          ),
          content: Text(
            isPromoting
                ? l10n.group_info_make_admin_body
                : l10n.group_info_remove_admin_body,
          ),
          actions: [
            TextButton(
              key: const ValueKey('group-role-change-cancel'),
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.btn_cancel),
            ),
            FilledButton(
              key: const ValueKey('group-role-change-confirm'),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(
                isPromoting
                    ? l10n.group_info_make_admin_action
                    : l10n.group_info_remove_admin_action,
              ),
            ),
          ],
        );
      },
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
            recoveryActiveDepthListenable:
                groupRecoveryGate.activeDepthListenable,
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
    // Snapshot for an honest rollback: if the local metadata is persisted but
    // the broadcast does not actually leave this device, we revert rather than
    // claim success while peers received nothing.
    GroupModel? preEditGroup;
    GroupModel? committedGroupForRecovery;
    GroupMembershipEffectAuthority? editAuthorityForRecovery;
    var metadataPersisted = false;
    String? committedTimelineMessageId;
    // Captured once the signed broadcast is built, so a post-persist failure can
    // durably enqueue it for retry instead of reverting (S2b).
    String? committedSysText;
    var committedRecipientPeerIds = const <String>[];
    String? committedSourceMessageId;
    final l10n = AppLocalizations.of(context)!;
    final noIdentityMessage = l10n.group_info_no_identity;
    final uploadPhotoFailedMessage = l10n.group_info_upload_photo_failed;
    final signMetadataFailedMessage = l10n.group_info_sign_metadata_failed;
    final recoveryWaitMessage = l10n.group_edit_recovery_waiting;
    final detailsUpdateFailedMessage = l10n.group_info_details_update_failed;
    final detailsUpdateQueuedMessage = l10n.group_info_details_update_queued;

    try {
      final identity = await widget.identityRepo.loadIdentity();
      if (identity == null) {
        throw StateError(noIdentityMessage);
      }
      final groupId = _group.id;
      final guardedUpload =
          await runSelfRemovedGroupLifecycleLeaf<_GroupInfoAvatarUploadPhase?>(
            groupRepo: widget.groupRepo,
            groupId: groupId,
            action: (currentGroup) async {
              if (currentGroup.isDissolved ||
                  currentGroup.myRole != GroupRole.admin) {
                return null;
              }
              final members = await widget.groupRepo.getMembers(groupId);
              final latestKey = await widget.groupRepo.getLatestKey(groupId);
              final authority = GroupMembershipEffectAuthority(
                group: currentGroup,
                members: members,
                latestKeyGeneration: latestKey?.keyGeneration,
              );
              final ownMember = authority.singleMember(identity.peerId);
              if (ownMember == null ||
                  !ownMember.permissions.allows(
                    GroupMemberPermission.editMetadata,
                    ownMember.role,
                  )) {
                return null;
              }
              if ((isRemovingAvatar || isReplacingAvatar) &&
                  isGroupRecoveryInProgress()) {
                throw StateError(groupRecoveryPendingError);
              }
              if (!isReplacingAvatar) {
                return _GroupInfoAvatarUploadPhase(authority: authority);
              }
              final uploaded = await widget.uploadGroupAvatarFn(
                bridge: widget.bridge,
                localFilePath: edit.preparedAvatarPath!,
                groupId: groupId,
                allowedPeers: groupMediaAllowedPeersForMembers(members),
                mime: 'image/jpeg',
              );
              if (uploaded == null) {
                throw StateError(uploadPhotoFailedMessage);
              }
              return _GroupInfoAvatarUploadPhase(
                authority: authority,
                uploaded: uploaded,
              );
            },
          );
      final uploadPhase = guardedUpload.value;
      if (!guardedUpload.didRun || uploadPhase == null) {
        throw StateError(detailsUpdateFailedMessage);
      }
      final editAuthority = uploadPhase.authority;
      editAuthorityForRecovery = editAuthority;
      preEditGroup = editAuthority.group;
      Future<bool> currentEditAuthorityMatches(GroupModel current) async {
        if (!_sameGroupMetadataSnapshot(current, editAuthority.group)) {
          return false;
        }
        final currentMembers = await widget.groupRepo.getMembers(groupId);
        final currentLatestKey = await widget.groupRepo.getLatestKey(groupId);
        return editAuthority.matches(
          GroupMembershipEffectAuthority(
            group: current,
            members: currentMembers,
            latestKeyGeneration: currentLatestKey?.keyGeneration,
          ),
        );
      }

      final senderBinding = await resolveGroupSenderDeviceBinding(
        groupRepo: widget.groupRepo,
        groupId: groupId,
        senderPeerId: identity.peerId,
        preferredDeviceId: _currentSenderDeviceId,
        preferredTransportPeerId: _currentSenderDeviceId,
        senderPublicKey: identity.publicKey,
      );
      final preTransitionStateHash = await buildGroupTransitionStateHash(
        widget.groupRepo,
        groupId,
      );

      String? avatarBlobId = editAuthority.group.avatarBlobId;
      String? avatarMime = editAuthority.group.avatarMime;
      String? avatarPath = editAuthority.group.avatarPath;
      String? preparedReplacementAvatarPath;
      if (isRemovingAvatar) {
        avatarBlobId = null;
        avatarMime = null;
        avatarPath = null;
      }
      if (isReplacingAvatar) {
        final uploaded = uploadPhase.uploaded!;
        preparedReplacementAvatarPath = edit.preparedAvatarPath!;
        avatarBlobId = uploaded.id;
        avatarMime = uploaded.mime;
        avatarPath = groupAvatarRelativePath(groupId);
      }

      List<GroupMember>? refreshedMembers;
      String? sysText;

      final authorityStillCurrent =
          await runGroupMembershipMutationLocked<bool>(
            groupId: groupId,
            action: () async {
              final current = await widget.groupRepo.getGroup(groupId);
              return current != null &&
                  current.isDissolved == false &&
                  current.selfRemovedAt == null &&
                  await currentEditAuthorityMatches(current);
            },
          );
      if (!authorityStillCurrent) {
        throw StateError(detailsUpdateFailedMessage);
      }

      final committedGroup = await updateGroupMetadata(
        groupRepo: widget.groupRepo,
        groupId: groupId,
        name: resolvedName,
        description: resolvedDescription,
        avatarBlobId: avatarBlobId,
        avatarMime: avatarMime,
        avatarPath: avatarPath,
        eventAt: changedAt,
        beforePersist: (updatedGroup) async {
          final membersForConfig = await widget.groupRepo.getMembers(groupId);
          final groupConfig = buildGroupConfigPayload(
            updatedGroup,
            membersForConfig,
          );
          final actorPayload = buildGroupMetadataActorEventPayload(
            groupId: groupId,
            updatedAt: changedAt,
            actorPeerId: identity.peerId,
            actorUsername: identity.username,
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
            throw StateError(signMetadataFailedMessage);
          }

          final sourceEventId =
              'group_metadata_updated:$groupId:${identity.peerId}:${changedAt.microsecondsSinceEpoch}';
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
            groupId: groupId,
            transitionType: 'group_metadata_updated',
            sourceEventId: sourceEventId,
            eventAt: changedAt,
            actorPeerId: identity.peerId,
            actorUsername: identity.username,
            actorSigningPublicKey: identity.publicKey,
            actorPrivateKey: identity.privateKey,
            actorDeviceId: senderBinding.deviceId,
            actorTransportPeerId: senderBinding.transportPeerId,
            actorKeyPackageId: senderBinding.keyPackageId,
            preTransitionStateHash: preTransitionStateHash,
            systemPayload: unsignedPayload,
          );

          if ((isRemovingAvatar || isReplacingAvatar) &&
              isGroupRecoveryInProgress()) {
            throw StateError(groupRecoveryPendingError);
          }
          if (isRemovingAvatar) {
            await deleteGroupAvatar(
              storedPath: editAuthority.group.avatarPath,
              groupId: groupId,
            );
          }
          final replacementPath = preparedReplacementAvatarPath;
          if (replacementPath != null) {
            await commitPreparedGroupAvatar(
              groupId: groupId,
              sourcePath: replacementPath,
              avatarNormalizer: AvatarNormalizationHelper(
                imageProcessor: widget.imageProcessor,
              ),
            );
          }

          refreshedMembers = membersForConfig;
          sysText = jsonEncode(signedPayload);
        },
        currentAuthorityCheck: currentEditAuthorityMatches,
      );
      committedGroupForRecovery = committedGroup;

      // The local DB now holds the new metadata (and the avatar file is
      // committed); from here a broadcast failure must roll this back.
      metadataPersisted = true;

      final signedSysText = sysText;
      final signedMembers = refreshedMembers;
      if (signedSysText == null || signedMembers == null) {
        throw StateError(signMetadataFailedMessage);
      }
      final metadataTimelineMessage = buildGroupMetadataUpdatedTimelineMessage(
        groupId: groupId,
        senderId: identity.peerId,
        senderUsername: identity.username,
        eventAt: changedAt,
      );

      if (widget.msgRepo != null) {
        await widget.msgRepo!.saveMessage(metadataTimelineMessage);
        committedTimelineMessageId = metadataTimelineMessage.id;
      }

      final sourceMessageId =
          'group_metadata_updated:$groupId:${identity.peerId}:${changedAt.microsecondsSinceEpoch}';
      final recipientPeerIds = signedMembers
          .where((member) => member.peerId != identity.peerId)
          .map((member) => member.peerId)
          .toList();
      // Capture the signed broadcast before publishing so the catch can durably
      // enqueue it for retry if it fails to leave the device.
      committedSysText = signedSysText;
      committedSourceMessageId = sourceMessageId;
      committedRecipientPeerIds = recipientPeerIds;

      final guardedPublish =
          await runSelfRemovedGroupLifecycleLeaf<Map<String, dynamic>?>(
            groupRepo: widget.groupRepo,
            groupId: groupId,
            action: (currentGroup) async {
              if (currentGroup.isDissolved ||
                  !_sameGroupMetadataSnapshot(currentGroup, committedGroup)) {
                return null;
              }
              final currentMembers = await widget.groupRepo.getMembers(groupId);
              final currentLatestKey = await widget.groupRepo.getLatestKey(
                groupId,
              );
              if (!editAuthority.matches(
                GroupMembershipEffectAuthority(
                  group: currentGroup,
                  members: currentMembers,
                  latestKeyGeneration: currentLatestKey?.keyGeneration,
                ),
              )) {
                return null;
              }
              return callGroupPublish(
                widget.bridge,
                groupId: groupId,
                text: signedSysText,
                senderPeerId: identity.peerId,
                senderPublicKey: identity.publicKey,
                senderPrivateKey: identity.privateKey,
                senderUsername: identity.username,
                senderDeviceId: senderBinding.deviceId,
                senderTransportPeerId: senderBinding.transportPeerId,
                senderDevicePublicKey: senderBinding.devicePublicKey,
                senderKeyPackageId: senderBinding.keyPackageId,
                messageId: sourceMessageId,
              );
            },
          );
      final publishResult = guardedPublish.value;
      if (!guardedPublish.didRun || publishResult == null) {
        throw StateError(detailsUpdateFailedMessage);
      }
      // [callGroupPublish] returns {ok:false} (e.g. BRIDGE_TIMEOUT) on a soft
      // failure instead of throwing; discarding it previously showed the
      // success snackbar while peers received nothing. Route soft failures
      // through the same revert/error path as a hard throw.
      if (publishResult['ok'] != true) {
        final publishError = publishResult['errorMessage']?.toString();
        throw StateError(
          publishError != null && publishError.isNotEmpty
              ? publishError
              : detailsUpdateFailedMessage,
        );
      }

      if (recipientPeerIds.isNotEmpty) {
        final inboxPayload = jsonEncode({
          'groupId': groupId,
          'senderId': identity.peerId,
          'senderUsername': identity.username,
          if (senderBinding.deviceId != null)
            'senderDeviceId': senderBinding.deviceId,
          if (senderBinding.transportPeerId != null)
            'transportPeerId': senderBinding.transportPeerId,
          'text': signedSysText,
          'timestamp': changedAt.toIso8601String(),
          'messageId': sourceMessageId,
        });
        final replayEnvelope = await buildGroupOfflineReplayEnvelope(
          bridge: widget.bridge,
          groupRepo: widget.groupRepo,
          groupId: groupId,
          payloadType: groupOfflineReplayPayloadTypeMessage,
          plaintext: inboxPayload,
          senderPeerId: identity.peerId,
          senderPublicKey: identity.publicKey,
          senderPrivateKey: identity.privateKey,
          senderDeviceId: senderBinding.deviceId,
          senderTransportPeerId: senderBinding.transportPeerId,
          senderKeyPackageId: senderBinding.keyPackageId,
          messageId: sourceMessageId,
          recipientPeerIds: recipientPeerIds,
        );
        await callGroupInboxStore(
          widget.bridge,
          groupId,
          replayEnvelope,
          recipientPeerIds: recipientPeerIds,
          preserveRecipientPeerIds: true,
        );
        final directTargets = groupMembershipUpdateDirectTargets(
          members: signedMembers,
          excludingPeerId: identity.peerId,
        );
        for (final target in directTargets) {
          unawaited(
            sendGroupMembershipUpdateDirect(
              sendP2PMessage: (peerId, message) async {
                return widget.p2pService.sendMessage(peerId, message);
              },
              recipientPeerId: target.deliveryPeerId,
              groupId: groupId,
              senderPeerId: identity.peerId,
              replayEnvelope: replayEnvelope,
              timestamp: changedAt,
              messageId: sourceMessageId,
            ),
          );
        }
      }

      await refreshPendingGroupInvitesForMetadataChange(
        p2pService: widget.p2pService,
        bridge: widget.bridge,
        groupRepo: widget.groupRepo,
        inviteDeliveryAttemptRepo: widget.inviteDeliveryAttemptRepo,
        identity: identity,
        groupId: groupId,
      );

      _didMutateGroup = true;
      await _loadGroupInfo();
      if (!mounted) return;
      // 154: _loadGroupInfo() already re-renders the name/description fields,
      // so the success snackbar was redundant. Confirm with a tactile
      // selectionClick; the snackbar channel stays reserved for the error /
      // rollback path below.
      HapticFeedback.selectionClick();
    } catch (e) {
      // If the metadata was persisted locally but the broadcast did not
      // succeed (hard throw OR soft publish failure), either durably enqueue
      // the signed broadcast for retry (S2b, when wired) keeping the local edit,
      // or roll the optimistic edit back (S2a fallback) — never report success
      // while peers received nothing.
      var enqueuedForRetry = false;
      if (metadataPersisted) {
        await runGroupMembershipMutationLocked<void>(
          groupId: _group.id,
          action: () async {
            final current = await widget.groupRepo.getGroup(_group.id);
            final expectedAuthority = editAuthorityForRecovery;
            final expectedCommitted = committedGroupForRecovery;
            var exactCurrent =
                current != null &&
                !current.isDissolved &&
                current.selfRemovedAt == null &&
                expectedAuthority != null &&
                expectedCommitted != null &&
                _sameGroupMetadataSnapshot(current, expectedCommitted);
            if (exactCurrent) {
              final currentMembers = await widget.groupRepo.getMembers(
                _group.id,
              );
              final currentLatestKey = await widget.groupRepo.getLatestKey(
                _group.id,
              );
              exactCurrent = expectedAuthority.matches(
                GroupMembershipEffectAuthority(
                  group: current,
                  members: currentMembers,
                  latestKeyGeneration: currentLatestKey?.keyGeneration,
                ),
              );
            }

            final timelineId = committedTimelineMessageId;
            if (!exactCurrent) {
              if (timelineId != null) {
                await widget.msgRepo?.deleteMessage(timelineId);
              }
              return;
            }

            final signedBroadcast = committedSysText;
            if (signedBroadcast != null &&
                hasGroupPendingBroadcastEnqueueSink) {
              final now = DateTime.now().toUtc();
              await enqueueGroupPendingBroadcast(
                GroupPendingBroadcast(
                  id: 'pending_group_broadcast:${_group.id}:$committedSourceMessageId',
                  groupId: _group.id,
                  kind: 'group_metadata_updated',
                  sysText: signedBroadcast,
                  recipientPeerIds: committedRecipientPeerIds,
                  eventAt: changedAt,
                  sourceMessageId: committedSourceMessageId,
                  createdAt: now,
                  updatedAt: now,
                ),
              );
              enqueuedForRetry = true;
              return;
            }

            final rollbackGroup = preEditGroup;
            if (rollbackGroup != null) {
              await widget.groupRepo.updateGroup(
                current!.copyWith(
                  name: rollbackGroup.name,
                  description: rollbackGroup.description,
                  avatarBlobId: rollbackGroup.avatarBlobId,
                  avatarMime: rollbackGroup.avatarMime,
                  avatarPath: rollbackGroup.avatarPath,
                  lastMetadataEventAt: rollbackGroup.lastMetadataEventAt,
                ),
              );
            }
            if (timelineId != null) {
              await widget.msgRepo?.deleteMessage(timelineId);
            }
          },
        );
      }
      emitFlowEvent(
        layer: 'FL',
        event: enqueuedForRetry
            ? 'GROUP_INFO_FL_METADATA_UPDATE_QUEUED'
            : 'GROUP_INFO_FL_METADATA_UPDATE_ERROR',
        details: {
          'groupId': _group.id.length > 8
              ? _group.id.substring(0, 8)
              : _group.id,
          'error': e.toString(),
        },
      );
      if (!mounted) return;
      final message = enqueuedForRetry
          ? detailsUpdateQueuedMessage
          : e is StateError
          ? e.message == groupRecoveryPendingError
                ? recoveryWaitMessage
                : e.message
          : detailsUpdateFailedMessage;
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
              uploadGroupAvatarFn: widget.uploadGroupAvatarFn,
              backgroundPreference: widget.backgroundPreference,
            ),
          ),
        )
        .then((result) {
          if (result != null && result.membersAdded > 0) {
            _didMutateGroup = true;
            _loadGroupInfo();
            if (mounted) {
              final l10n = AppLocalizations.of(context)!;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(result.buildCompletionMessage(l10n))),
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

    // Captured pre-gap: thrown after awaits, when this State may be unmounted.
    final noIdentityError = AppLocalizations.of(
      context,
    )!.group_info_no_identity;
    setState(() => _resendingInvitePeerIds.add(member.peerId));
    try {
      final identity = await widget.identityRepo.loadIdentity();
      if (identity == null) {
        throw StateError(noIdentityError);
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
      final updatedAttempt = _inviteAttemptsByPeerId[member.peerId];
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _resendInviteMessage(
              member,
              result,
              lastError: updatedAttempt?.lastError,
            ),
          ),
        ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.group_info_invite_resend_failed,
          ),
        ),
      );
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
    ResendGroupInviteResult result, {
    String? lastError,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final name = _displayName(member);
    switch (result.status) {
      case GroupInviteDeliveryStatus.sent:
        return l10n.group_info_invite_sent(name);
      case GroupInviteDeliveryStatus.queued:
        return l10n.group_info_invite_queued(name);
      case GroupInviteDeliveryStatus.needsResend:
        return l10n.group_info_invite_needs_resend;
      case GroupInviteDeliveryStatus.cannotSend:
        return groupInviteCannotSendSnackBarMessage(l10n, lastError);
      case GroupInviteDeliveryStatus.joined:
        return l10n.group_info_invite_joined(name);
      case GroupInviteDeliveryStatus.revoked:
      case GroupInviteDeliveryStatus.declined:
      case GroupInviteDeliveryStatus.unknown:
        return l10n.group_info_invite_unknown;
    }
  }

  /// Pre-confirm the irreversible invite revocation (mirrors
  /// [_confirmRoleChange]). The signed revocation envelope is put on the wire
  /// only after the admin confirms — there is NO Undo (153 INV-1/INV-2).
  Future<void> _confirmRevokeInvite(GroupMember member) async {
    if (!mounted) return;

    final shouldRevoke = await showDialog<bool>(
      context: context,
      builder: (context) {
        final l10n = AppLocalizations.of(context)!;
        final name = _displayName(member);
        return AlertDialog(
          title: Text(l10n.group_info_revoke_invite_title(name)),
          content: Text(l10n.group_info_revoke_invite_body),
          actions: [
            TextButton(
              key: const ValueKey('group-revoke-cancel'),
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.btn_cancel),
            ),
            FilledButton(
              key: const ValueKey('group-revoke-confirm'),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.group_info_revoke_invite_action),
            ),
          ],
        );
      },
    );

    if (shouldRevoke == true) {
      await _onRevokeInvite(member);
    }
  }

  Future<void> _onRevokeInvite(GroupMember member) async {
    final repo = widget.inviteDeliveryAttemptRepo;
    if (repo == null || _revokingInvitePeerIds.contains(member.peerId)) {
      return;
    }

    // Capture l10n synchronously before any await so it can be used after the
    // identity load without an across-async-gap context access.
    final l10n = AppLocalizations.of(context)!;
    setState(() => _revokingInvitePeerIds.add(member.peerId));
    try {
      final identity = await widget.identityRepo.loadIdentity();
      if (identity == null) {
        throw StateError(l10n.group_info_no_identity);
      }
      // HOLE-4: the receiver only deletes its live pending invite when the
      // revocation carries the exact invite id it was sent. That id is
      // persisted on the delivery-attempt row at send time.
      final inviteId = _inviteAttemptsByPeerId[member.peerId]?.inviteId;
      final result = await sendGroupInviteRevocation(
        p2pService: widget.p2pService,
        bridge: widget.bridge,
        inviteId: inviteId ?? '',
        groupId: _group.id,
        recipientPeerId: member.peerId,
        recipientMlKemPublicKey: member.mlKemPublicKey,
        senderPeerId: identity.peerId,
        senderPublicKey: identity.publicKey,
        senderPrivateKey: identity.privateKey,
        groupConfig: _buildGroupConfig(_group, _members),
      );
      if (result == SendGroupInviteRevocationResult.success) {
        await repo.markRevoked(groupId: _group.id, peerId: member.peerId);
      }
      await _loadGroupInfo();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_revokeInviteMessage(member, result))),
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_INFO_FL_REVOKE_INVITE_ERROR',
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.group_info_invite_revoke_failed,
          ),
        ),
      );
      await _loadGroupInfo();
    } finally {
      if (mounted) {
        setState(() => _revokingInvitePeerIds.remove(member.peerId));
      } else {
        _revokingInvitePeerIds.remove(member.peerId);
      }
    }
  }

  String _revokeInviteMessage(
    GroupMember member,
    SendGroupInviteRevocationResult result,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final name = _displayName(member);
    switch (result) {
      case SendGroupInviteRevocationResult.success:
        return l10n.group_info_invite_revoked(name);
      case SendGroupInviteRevocationResult.nodeNotRunning:
      case SendGroupInviteRevocationResult.encryptionRequired:
      case SendGroupInviteRevocationResult.invalidPayload:
      case SendGroupInviteRevocationResult.sendFailed:
        return l10n.group_info_invite_revoke_failed;
    }
  }

  void _onBack() {
    Navigator.of(context).pop(_didMutateGroup);
  }

  Future<void> _openSharedMedia() async {
    final routeBuilder = widget.sharedMediaRouteBuilder;
    if (routeBuilder == null) return;
    final live = await resolveGroupSharedMediaRoute(
      groupId: _group.id,
      loadGroup: widget.groupRepo.getGroup,
      includeAnnouncements: true,
    );
    if (!mounted || live == null) return;
    final result = await Navigator.of(context)
        .push<GroupSharedMediaLibraryResult>(
          MaterialPageRoute(builder: (context) => routeBuilder(context, live)),
        );
    if (!mounted || result == null) return;
    Navigator.of(context).pop(result);
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
      inviteAttemptsByPeerId: _inviteAttemptsByPeerId,
      resendingInvitePeerIds: _resendingInvitePeerIds,
      revokingInvitePeerIds: _revokingInvitePeerIds,
      memberSafetyByPeerId: _memberSafetyByPeerId,
      securityStatus: _securityStatus,
      pendingSiblingDevices: _pendingSiblingDeviceViews,
      onVerifyPendingSiblingDevice: _onVerifyPendingSiblingDevice,
      onRejectPendingSiblingDevice: _onRejectPendingSiblingDevice,
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
      onOpenSharedMedia:
          widget.sharedMediaRouteBuilder != null &&
              (_group.type == GroupType.chat ||
                  _group.type == GroupType.announcement) &&
              !_group.isDissolved
          ? _openSharedMedia
          : null,
      onResendInvite: canManageGroup && widget.inviteDeliveryAttemptRepo != null
          ? _onResendInvite
          : null,
      onRevokeInvite: canManageGroup && widget.inviteDeliveryAttemptRepo != null
          ? _confirmRevokeInvite
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
    return AppLocalizations.of(context)!.group_info_member_fallback;
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
  final ValueListenable<int> recoveryActiveDepthListenable;

  const _GroupMetadataEditorSheet({
    required this.group,
    required this.mediaPicker,
    required this.imageProcessor,
    required this.recoveryActiveDepthListenable,
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
  int _recoveryActiveDepth = 0;
  int _recoveryWaitSeconds = 0;
  Timer? _recoveryWaitTimer;

  bool get _hasCurrentAvatar =>
      widget.group.avatarBlobId != null ||
      widget.group.avatarPath != null ||
      _previewBytes != null;
  bool get _isRecoveryActive => _recoveryActiveDepth > 0;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.group.name);
    _descriptionController = TextEditingController(
      text: widget.group.description ?? '',
    );
    _recoveryActiveDepth = widget.recoveryActiveDepthListenable.value;
    widget.recoveryActiveDepthListenable.addListener(
      _handleRecoveryDepthChanged,
    );
    _syncRecoveryWaitTimer();
  }

  @override
  void didUpdateWidget(covariant _GroupMetadataEditorSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.recoveryActiveDepthListenable !=
        widget.recoveryActiveDepthListenable) {
      oldWidget.recoveryActiveDepthListenable.removeListener(
        _handleRecoveryDepthChanged,
      );
      widget.recoveryActiveDepthListenable.addListener(
        _handleRecoveryDepthChanged,
      );
      _handleRecoveryDepthChanged();
    }
  }

  @override
  void dispose() {
    widget.recoveryActiveDepthListenable.removeListener(
      _handleRecoveryDepthChanged,
    );
    _recoveryWaitTimer?.cancel();
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _handleRecoveryDepthChanged() {
    if (!mounted) {
      return;
    }
    final activeDepth = widget.recoveryActiveDepthListenable.value;
    setState(() {
      _recoveryActiveDepth = activeDepth;
      if (activeDepth > 0 && _recoveryWaitTimer == null) {
        _recoveryWaitSeconds = 0;
      } else if (activeDepth == 0) {
        _recoveryWaitSeconds = 0;
      }
    });
    _syncRecoveryWaitTimer();
  }

  void _syncRecoveryWaitTimer() {
    if (_isRecoveryActive) {
      _recoveryWaitTimer ??= Timer.periodic(
        const Duration(seconds: 1),
        (_) => _tickRecoveryWait(),
      );
      return;
    }
    _recoveryWaitTimer?.cancel();
    _recoveryWaitTimer = null;
  }

  void _tickRecoveryWait() {
    if (!mounted || !_isRecoveryActive) {
      return;
    }
    setState(() => _recoveryWaitSeconds += 1);
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
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.group_edit_photo_pick_failed,
          ),
        ),
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
    if (resolvedName.isEmpty || _isRecoveryActive) {
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
    final l10n = AppLocalizations.of(context)!;
    final isSaveDisabled =
        _nameController.text.trim().isEmpty || _isRecoveryActive;

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
                l10n.group_edit_details_title,
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
                            ? l10n.group_edit_change_photo
                            : l10n.group_edit_add_photo,
                      ),
                    ),
                    if (_hasCurrentAvatar || _removeAvatar)
                      TextButton(
                        key: const ValueKey('group-edit-remove-photo'),
                        onPressed: _removePhoto,
                        child: Text(l10n.group_edit_remove_photo),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                l10n.group_edit_name,
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
                l10n.group_edit_description,
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
              if (_isRecoveryActive) ...[
                Text(
                  l10n.group_edit_recovery_waiting,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: readableColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.group_edit_recovery_waiting_elapsed(
                    _recoveryWaitSeconds,
                  ),
                  style: TextStyle(
                    fontSize: 12,
                    color: readableColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: const ValueKey('group-edit-cancel'),
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(l10n.btn_cancel),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      key: const ValueKey('group-edit-save'),
                      onPressed: isSaveDisabled ? null : _save,
                      child: Text(l10n.btn_save),
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
          // The surrounding container paints the fill; the light theme's
          // filled InputDecorationTheme would otherwise paint a square fill
          // rect on top of it.
          filled: false,
          contentPadding: const EdgeInsets.all(14),
          hintStyle: TextStyle(color: readableColors.placeholderText),
        ),
      ),
    );
  }
}
