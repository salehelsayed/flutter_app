import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/groups/domain/models/group_welcome_key_package.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

/// One immutable local-identity view for validating a single incoming invite.
///
/// The account identity and its ML-KEM material come from one repository read,
/// while the device/transport binding comes from one [P2PService.currentState]
/// snapshot. Consumers must use the whole tuple rather than mixing individual
/// callbacks across mutable node-state transitions.
final class GroupInviteLocalIdentitySnapshot {
  final String? accountPeerId;
  final String? deviceId;
  final String? transportPeerId;
  final String? mlKemPublicKey;
  final String? mlKemSecretKey;
  final String? keyPackageId;
  final String? keyPackagePublicMaterial;

  const GroupInviteLocalIdentitySnapshot({
    required this.accountPeerId,
    required this.deviceId,
    required this.transportPeerId,
    required this.mlKemPublicKey,
    required this.mlKemSecretKey,
    required this.keyPackageId,
    required this.keyPackagePublicMaterial,
  });
}

/// Bundle of identity callbacks shared across the group listeners
/// (GroupInviteListener, GroupKeyUpdateListener, etc.).
///
/// Reads device identity from the identity repository so the values are
/// available the moment the user's identity is loaded — long before
/// `p2pService.startNode()` populates `currentState.peerId`. Once the node is
/// live, its peer ID is the authoritative device/transport binding; the
/// account peer ID remains the cold-start fallback for legacy single-device
/// identities.
class GroupIdentityCallbacks {
  final Future<GroupInviteLocalIdentitySnapshot> Function()
  loadOwnInviteIdentity;
  final Future<String?> Function() getOwnPeerId;
  final Future<String?> Function() getOwnDeviceId;
  final Future<String?> Function() getOwnTransportPeerId;
  final Future<String?> Function() getOwnMlKemPublicKey;
  final Future<String?> Function() getOwnMlKemSecretKey;
  final Future<String?> Function() getOwnKeyPackageId;
  final Future<String?> Function() getOwnKeyPackagePublicMaterial;

  const GroupIdentityCallbacks({
    required this.loadOwnInviteIdentity,
    required this.getOwnPeerId,
    required this.getOwnDeviceId,
    required this.getOwnTransportPeerId,
    required this.getOwnMlKemPublicKey,
    required this.getOwnMlKemSecretKey,
    required this.getOwnKeyPackageId,
    required this.getOwnKeyPackagePublicMaterial,
  });
}

/// Loads one coherent identity tuple for a single incoming group invite.
Future<GroupInviteLocalIdentitySnapshot> loadGroupInviteLocalIdentitySnapshot({
  required IdentityRepository identityRepo,
  required P2PService p2pService,
}) async {
  final identity = await identityRepo.loadIdentity();
  final nodeState = p2pService.currentState;

  final liveTransportPeerId = nodeState.isStarted
      ? nodeState.peerId?.trim()
      : null;
  final hasLiveTransport =
      liveTransportPeerId != null && liveTransportPeerId.isNotEmpty;
  final accountPeerId = identity?.peerId;
  final deviceId = identity == null
      ? null
      : (hasLiveTransport ? liveTransportPeerId : accountPeerId);
  final mlKemPublicKey = identity?.mlKemPublicKey;

  return GroupInviteLocalIdentitySnapshot(
    accountPeerId: accountPeerId,
    deviceId: deviceId,
    transportPeerId: deviceId,
    mlKemPublicKey: mlKemPublicKey,
    mlKemSecretKey: identity?.mlKemSecretKey,
    keyPackageId: defaultGroupWelcomeKeyPackageIdForDevice(deviceId),
    keyPackagePublicMaterial: mlKemPublicKey,
  );
}

GroupIdentityCallbacks buildGroupIdentityCallbacks({
  required IdentityRepository identityRepo,
  required P2PService p2pService,
}) {
  Future<GroupInviteLocalIdentitySnapshot> inviteIdentity() =>
      loadGroupInviteLocalIdentitySnapshot(
        identityRepo: identityRepo,
        p2pService: p2pService,
      );

  Future<String?> peerId() async {
    final identity = await identityRepo.loadIdentity();
    return identity?.peerId;
  }

  Future<String?> deviceId() async {
    final nodeState = p2pService.currentState;
    final transportPeerId = nodeState.isStarted
        ? nodeState.peerId?.trim()
        : null;
    if (transportPeerId != null && transportPeerId.isNotEmpty) {
      return transportPeerId;
    }
    return peerId();
  }

  return GroupIdentityCallbacks(
    loadOwnInviteIdentity: inviteIdentity,
    getOwnPeerId: peerId,
    getOwnDeviceId: deviceId,
    getOwnTransportPeerId: deviceId,
    getOwnMlKemPublicKey: () async {
      final identity = await identityRepo.loadIdentity();
      return identity?.mlKemPublicKey;
    },
    getOwnMlKemSecretKey: () async {
      final identity = await identityRepo.loadIdentity();
      return identity?.mlKemSecretKey;
    },
    getOwnKeyPackageId: () async {
      return defaultGroupWelcomeKeyPackageIdForDevice(await deviceId());
    },
    getOwnKeyPackagePublicMaterial: () async {
      final identity = await identityRepo.loadIdentity();
      return identity?.mlKemPublicKey;
    },
  );
}
