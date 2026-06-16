import 'package:flutter_app/core/config/multi_device_sync_flag.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_member_identity_safety.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

/// B4 (R3) read-path resolver for a member's device-aware safety status.
///
/// When a per-group device-set snapshot store is available, this folds the
/// member's per-device key material into the safety number + the identityChanged
/// flag, using TOFU: on the FIRST observation of a member (no snapshot yet) the
/// current active device set is persisted as the trusted baseline, so it does not
/// spuriously flag as changed. A later device add/swap then diverges from the
/// saved baseline and surfaces a warning (until a verify action re-baselines it).
///
/// When [snapshotRepo] is null (no storage / older fakes) this is exactly the
/// previous account-level (v1) behaviour.
Future<GroupMemberIdentitySafety?> resolveGroupMemberDeviceSafety({
  required GroupMember member,
  required ContactModel? savedContact,
  GroupMemberDeviceSnapshotRepository? snapshotRepo,
  DateTime Function()? nowUtc,
  // The per-device dimension is part of the multi-device convergence build and is
  // a user-facing security-string change (v1→v2), so it is gated by the flag: OFF
  // (the default, every current user) keeps the exact account-level v1 number,
  // avoiding cross-version safety-number mismatches during a mixed rollout.
  bool multiDeviceSyncEnabled = kMultiDeviceSyncEnabled,
}) async {
  if (!multiDeviceSyncEnabled || snapshotRepo == null) {
    return GroupMemberIdentitySafety.compare(
      member: member,
      savedContact: savedContact,
    );
  }

  var savedDevices = await snapshotRepo.loadGroupMemberDeviceSnapshot(
    member.groupId,
    member.peerId,
  );
  if (savedDevices == null) {
    // TOFU: trust the current device set as the baseline on first observe.
    await snapshotRepo.saveGroupMemberDeviceSnapshot(
      member,
      savedAt: (nowUtc ?? () => DateTime.now().toUtc())(),
    );
    savedDevices = member.activeDevicesWithLegacyFallback();
  }

  return GroupMemberIdentitySafety.compare(
    member: member,
    savedContact: savedContact,
    savedDevices: savedDevices,
  );
}

/// Casts a [GroupRepository] to the optional device-snapshot capability, or null.
GroupMemberDeviceSnapshotRepository? asGroupMemberDeviceSnapshotRepository(
  GroupRepository repo,
) => repo is GroupMemberDeviceSnapshotRepository
    ? repo as GroupMemberDeviceSnapshotRepository
    : null;
