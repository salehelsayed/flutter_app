import 'package:flutter_app/core/config/multi_device_sync_flag.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/group_pending_key_distribution_service.dart';
import 'package:flutter_app/features/groups/application/rotate_and_distribute_group_key_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

typedef TriggerDeferredDistributionDrainForPeerFn =
    Future<void> Function({required String groupId, required String peerId});

typedef EnqueueDeferredGroupKeyDistributionFn =
    Future<void> Function({
      required String groupId,
      required String peerId,
      required int keyEpoch,
    });

/// Injection seam for [admitSiblingDeviceIfTrusted] at the listener dispatch
/// site. Declares only the receiver-facing params; the real function's extra
/// optional params (flag/enqueue/drain) default in production and a test spy
/// implements just this surface.
typedef AdmitSiblingDeviceFn =
    Future<SiblingDeviceAdmissionOutcome> Function({
      required GroupRepository groupRepo,
      required String groupId,
      required String memberPeerId,
      required String announcedDeviceId,
      required String announcedTransportPeerId,
      required String announcedDeviceSigningPublicKey,
      required String verifiedAccountSigningPublicKey,
      String? announcedMlKemPublicKey,
      String? announcedKeyPackageId,
      String? announcedKeyPackagePublicMaterial,
    });

enum SiblingDeviceAdmissionOutcome {
  /// A genuinely new sibling device was added to the member's roster and the
  /// per-device key distribution drain was triggered for it.
  admitted,

  /// The device (by id or transport peer id, incl. the legacy account-derived
  /// device) is already on the roster — no write.
  alreadyPresent,

  /// The announced device's account signature key does not match the member's
  /// trusted account public key — refused.
  rejectedUntrusted,

  /// `multiDeviceSync` is off — admission is a no-op.
  disabled,

  /// No member with [memberPeerId] exists in the group.
  memberNotFound,

  /// The announced device is missing required identity fields.
  invalidDevice,

  /// The device was already admitted by the atomic linked-group bootstrap.
  /// Its v85 row remains protected retry intent until exact relay custody and
  /// must not enter generic key redistribution or deletion.
  protectedBootstrapOwned,
}

/// B1b keystone (Part B of `12-P2-multi-device-honesty.md`): admit a same-user
/// **sibling** device into a group member's device roster so the existing,
/// durable per-device key-distribution runner re-distributes the current group
/// key to it.
///
/// Re-distribution itself is already built and wired
/// (`distributeCurrentGroupKeyToDeferredPeer` +
/// `GroupPendingKeyDistributionRunner`, driven by
/// [triggerDeferredDistributionDrainForPeer]). The one gap that runner cannot
/// close is that a device the roster has never seen is never a delivery target.
/// This use case fills exactly that gap — it makes the new device *deliverable*
/// and then nudges the existing runner; it does not re-implement distribution.
///
/// Trust + safety model:
/// - Gated behind [kMultiDeviceSyncEnabled] (default-OFF). The flag value is
///   injectable ([multiDeviceSyncEnabled]) only so the logic is unit-testable —
///   production callers omit it and inherit the compile-time const, so this is
///   inert in shipped builds until the convergence build is enabled and
///   device-matrix verified.
/// - Cryptographic trust gate: [verifiedAccountSigningPublicKey] (the account
///   key that signed the device announce, already verified upstream) MUST equal
///   the member's account public key. This is the "first-use-on-trusted-account-
///   key" admission the proposal specifies. A UI safety-number prompt and/or an
///   admin-signed device-add transition is the REQUIRED wrapper above this
///   primitive before the flag is enabled — auto-admitting any account-signed
///   device is otherwise a self-compromise vector.
/// - Idempotent: a device already on the roster (by id or transport peer id,
///   including the legacy account-derived device) is a no-op. A same-`peerId`
///   sibling carrying no distinct per-device key is therefore correctly NOT
///   re-admitted — admission only adds genuinely new per-device identities.
Future<SiblingDeviceAdmissionOutcome> admitSiblingDeviceIfTrusted({
  required GroupRepository groupRepo,
  required String groupId,
  required String memberPeerId,
  required String announcedDeviceId,
  required String announcedTransportPeerId,
  required String announcedDeviceSigningPublicKey,
  required String verifiedAccountSigningPublicKey,
  String? announcedMlKemPublicKey,
  String? announcedKeyPackageId,
  String? announcedKeyPackagePublicMaterial,
  bool multiDeviceSyncEnabled = kMultiDeviceSyncEnabled,
  EnqueueDeferredGroupKeyDistributionFn reopenDeferredDistribution =
      triggerDeferredGroupKeyDistributionReopen,
  TriggerDeferredDistributionDrainForPeerFn triggerDrain =
      triggerDeferredDistributionDrainForPeer,
}) async {
  if (!multiDeviceSyncEnabled) {
    return SiblingDeviceAdmissionOutcome.disabled;
  }

  final deviceId = announcedDeviceId.trim();
  final transportPeerId = announcedTransportPeerId.trim();
  final signingKey = announcedDeviceSigningPublicKey.trim();
  if (deviceId.isEmpty || transportPeerId.isEmpty || signingKey.isEmpty) {
    return SiblingDeviceAdmissionOutcome.invalidDevice;
  }

  final member = await groupRepo.getMember(groupId, memberPeerId);
  if (member == null) {
    return SiblingDeviceAdmissionOutcome.memberNotFound;
  }

  final trustedAccountKey = member.publicKey?.trim();
  final verifiedKey = verifiedAccountSigningPublicKey.trim();
  if (trustedAccountKey == null ||
      trustedAccountKey.isEmpty ||
      verifiedKey.isEmpty ||
      trustedAccountKey != verifiedKey) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_SIBLING_DEVICE_ADMISSION_REJECTED_UNTRUSTED',
      details: {
        'groupId': _safe(groupId),
        'memberPeerId': _safe(memberPeerId),
        'deviceId': _safe(deviceId),
      },
    );
    return SiblingDeviceAdmissionOutcome.rejectedUntrusted;
  }

  // Idempotency: treat the legacy account-derived device as present too, so a
  // same-peerId sibling (no distinct key) is never spuriously re-admitted.
  final existingById = member.findDeviceById(
    deviceId,
    activeOnly: false,
    allowLegacyFallback: true,
  );
  final existingByTransport = member.findDeviceByTransportPeerId(
    transportPeerId,
    activeOnly: false,
    allowLegacyFallback: true,
  );
  final alreadyPresent = existingById != null || existingByTransport != null;
  if (alreadyPresent) {
    // Same-peerId sibling with no distinct key (covered by the legacy
    // account-derived device): nothing to deliver, no-op.
    final legacyOnly =
        (existingById?.deviceId == memberPeerId) ||
        (existingByTransport?.transportPeerId == memberPeerId);
    if (legacyOnly) {
      return SiblingDeviceAdmissionOutcome.alreadyPresent;
    }
  } else {
    final newDevice = GroupMemberDeviceIdentity(
      deviceId: deviceId,
      transportPeerId: transportPeerId,
      deviceSigningPublicKey: signingKey,
      mlKemPublicKey: _trimToNull(announcedMlKemPublicKey),
      keyPackageId: _trimToNull(announcedKeyPackageId),
      keyPackagePublicMaterial: _trimToNull(announcedKeyPackagePublicMaterial),
    );
    await groupRepo.saveMember(
      member.copyWith(devices: [...member.devices, newDevice]),
    );
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_SIBLING_DEVICE_ADMITTED',
      details: {
        'groupId': _safe(groupId),
        'memberPeerId': _safe(memberPeerId),
        'deviceId': _safe(deviceId),
        'deviceCount': member.devices.length + 1,
      },
    );
  }

  // Reuse the existing durable per-device distribution machinery to deliver the
  // CURRENT group key to the device. The drain alone is not enough: it only
  // processes PENDING rows, and (a) an already-keyed member has none, while
  // (b) a previously-delivered member's (group,peer) row is already terminal —
  // both leave a newly-admitted device keyless. So REOPEN the durable row to
  // pending at the current epoch (the device set changed), THEN drain — the
  // runner re-distributes the current key to the member's deliverable devices,
  // including this one. This also re-arms a row that was exhausted ('unreachable')
  // while the target was offline, so a later re-announce converges.
  //
  // Both fire on re-admit too (alreadyPresent for a DISTINCT device), so a repeat
  // announce re-arms delivery instead of no-oping forever. If no key exists yet
  // locally the reopen is skipped — that case converges via the NEXT group key
  // rotation, which enumerates each member's active devices (NOT via the
  // app-resume drain, which only re-processes pre-existing pending rows). Both
  // triggers swallow sink errors, so neither blocks admission.
  final latestKey = await groupRepo.getLatestKey(groupId);
  if (latestKey != null) {
    await reopenDeferredDistribution(
      groupId: groupId,
      peerId: memberPeerId,
      keyEpoch: latestKey.keyGeneration,
    );
    await triggerDrain(groupId: groupId, peerId: memberPeerId);
  }

  return alreadyPresent
      ? SiblingDeviceAdmissionOutcome.alreadyPresent
      : SiblingDeviceAdmissionOutcome.admitted;
}

String _safe(String value) => value.length > 8 ? value.substring(0, 8) : value;

String? _trimToNull(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}
