import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/groups/domain/models/group_welcome_key_package.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

/// Bundle of identity callbacks shared across the group listeners
/// (GroupInviteListener, GroupKeyUpdateListener, etc.).
///
/// Reads device identity from the identity repository so the values are
/// available the moment the user's identity is loaded — long before
/// `p2pService.startNode()` populates `currentState.peerId`. The
/// `p2pService` parameter is accepted for future extensibility (e.g., if
/// transport-only fields ever diverge from identity-derived ones), but
/// today nothing should reach into its mutable runtime state for these
/// security-critical callbacks.
class GroupIdentityCallbacks {
  final Future<String?> Function() getOwnPeerId;
  final Future<String?> Function() getOwnDeviceId;
  final Future<String?> Function() getOwnTransportPeerId;
  final Future<String?> Function() getOwnMlKemPublicKey;
  final Future<String?> Function() getOwnMlKemSecretKey;
  final Future<String?> Function() getOwnKeyPackageId;
  final Future<String?> Function() getOwnKeyPackagePublicMaterial;

  const GroupIdentityCallbacks({
    required this.getOwnPeerId,
    required this.getOwnDeviceId,
    required this.getOwnTransportPeerId,
    required this.getOwnMlKemPublicKey,
    required this.getOwnMlKemSecretKey,
    required this.getOwnKeyPackageId,
    required this.getOwnKeyPackagePublicMaterial,
  });
}

GroupIdentityCallbacks buildGroupIdentityCallbacks({
  required IdentityRepository identityRepo,
  required P2PService p2pService,
}) {
  Future<String?> peerId() async {
    final identity = await identityRepo.loadIdentity();
    return identity?.peerId;
  }

  return GroupIdentityCallbacks(
    getOwnPeerId: peerId,
    getOwnDeviceId: peerId,
    getOwnTransportPeerId: peerId,
    getOwnMlKemPublicKey: () async {
      final identity = await identityRepo.loadIdentity();
      return identity?.mlKemPublicKey;
    },
    getOwnMlKemSecretKey: () async {
      final identity = await identityRepo.loadIdentity();
      return identity?.mlKemSecretKey;
    },
    getOwnKeyPackageId: () async {
      final identity = await identityRepo.loadIdentity();
      return defaultGroupWelcomeKeyPackageIdForDevice(identity?.peerId);
    },
    getOwnKeyPackagePublicMaterial: () async {
      final identity = await identityRepo.loadIdentity();
      return identity?.mlKemPublicKey;
    },
  );
}
