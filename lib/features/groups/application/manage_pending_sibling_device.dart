import 'package:flutter_app/core/config/multi_device_sync_flag.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/admit_sibling_device_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/pending_sibling_device.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/pending_sibling_device_repository.dart';

/// Injection seam for the listener: hold an account-signed sibling-device
/// announce for an explicit user trust decision (R2). Never throws.
typedef HoldPendingSiblingDeviceFn =
    Future<void> Function({
      required String groupId,
      required String memberPeerId,
      required String announcedDeviceId,
      required String announcedTransportPeerId,
      required String announcedDeviceSigningPublicKey,
      required String verifiedAccountSigningPublicKey,
      String? announcedMlKemPublicKey,
      String? announcedKeyPackageId,
    });

/// R2: hold a verified sibling-device announce as PENDING a user decision,
/// instead of auto-admitting it. This is the trust wrapper the proposal requires
/// above the raw [admitSiblingDeviceIfTrusted] primitive — auto-admitting any
/// account-signed device is a self-compromise vector.
///
/// Flag-gated (injectable [multiDeviceSyncEnabled]); no-op for a device already
/// on the member's roster (already trusted). Never throws.
Future<void> holdPendingSiblingDevice({
  required PendingSiblingDeviceRepository pendingRepo,
  required GroupRepository groupRepo,
  required String groupId,
  required String memberPeerId,
  required String announcedDeviceId,
  required String announcedTransportPeerId,
  required String announcedDeviceSigningPublicKey,
  required String verifiedAccountSigningPublicKey,
  String? announcedMlKemPublicKey,
  String? announcedKeyPackageId,
  DateTime Function()? nowUtc,
  bool multiDeviceSyncEnabled = kMultiDeviceSyncEnabled,
}) async {
  if (!multiDeviceSyncEnabled) {
    return;
  }
  try {
    final member = await groupRepo.getMember(groupId, memberPeerId);
    if (member != null) {
      final existing =
          member.findDeviceById(
            announcedDeviceId,
            activeOnly: false,
            allowLegacyFallback: true,
          ) ??
          member.findDeviceByTransportPeerId(
            announcedTransportPeerId,
            activeOnly: false,
            allowLegacyFallback: true,
          );
      if (existing != null) {
        // Already on the roster (trusted) — nothing to hold.
        return;
      }
    }
    await pendingRepo.savePendingSiblingDevice(
      PendingSiblingDevice(
        groupId: groupId,
        memberPeerId: memberPeerId,
        deviceId: announcedDeviceId,
        transportPeerId: announcedTransportPeerId,
        deviceSigningPublicKey: announcedDeviceSigningPublicKey,
        mlKemPublicKey: announcedMlKemPublicKey,
        keyPackageId: announcedKeyPackageId,
        verifiedAccountSigningPublicKey: verifiedAccountSigningPublicKey,
        announcedAt: (nowUtc ?? () => DateTime.now().toUtc())(),
      ),
    );
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_SIBLING_DEVICE_HELD_PENDING',
      details: {
        'groupId': _safe(groupId),
        'memberPeerId': _safe(memberPeerId),
        'deviceId': _safe(announcedDeviceId),
      },
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_SIBLING_DEVICE_HOLD_ERROR',
      details: {'error': e.toString()},
    );
  }
}

/// R2: the user verified a pending sibling device — admit it (via the trust-gated
/// primitive) and clear it from the pending list once acted on.
Future<SiblingDeviceAdmissionOutcome> verifyAndAdmitPendingSiblingDevice({
  required PendingSiblingDeviceRepository pendingRepo,
  required GroupRepository groupRepo,
  required PendingSiblingDevice pending,
  bool multiDeviceSyncEnabled = kMultiDeviceSyncEnabled,
}) async {
  final outcome = await admitSiblingDeviceIfTrusted(
    groupRepo: groupRepo,
    groupId: pending.groupId,
    memberPeerId: pending.memberPeerId,
    announcedDeviceId: pending.deviceId,
    announcedTransportPeerId: pending.transportPeerId,
    announcedDeviceSigningPublicKey: pending.deviceSigningPublicKey,
    verifiedAccountSigningPublicKey: pending.verifiedAccountSigningPublicKey,
    announcedMlKemPublicKey: pending.mlKemPublicKey,
    announcedKeyPackageId: pending.keyPackageId,
    multiDeviceSyncEnabled: multiDeviceSyncEnabled,
  );
  if (outcome == SiblingDeviceAdmissionOutcome.admitted ||
      outcome == SiblingDeviceAdmissionOutcome.alreadyPresent) {
    await pendingRepo.deletePendingSiblingDevice(
      pending.groupId,
      pending.memberPeerId,
      pending.deviceId,
    );
  }
  return outcome;
}

/// R2: the user rejected a pending sibling device — drop it from the pending list
/// (it is never admitted).
Future<void> rejectPendingSiblingDevice({
  required PendingSiblingDeviceRepository pendingRepo,
  required PendingSiblingDevice pending,
}) async {
  await pendingRepo.deletePendingSiblingDevice(
    pending.groupId,
    pending.memberPeerId,
    pending.deviceId,
  );
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_SIBLING_DEVICE_REJECTED',
    details: {
      'groupId': _safe(pending.groupId),
      'deviceId': _safe(pending.deviceId),
    },
  );
}

String _safe(String value) => value.length > 8 ? value.substring(0, 8) : value;
