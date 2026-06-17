/// R2 (12-P2): a same-user sibling device that announced itself (account-signed)
/// and is awaiting an explicit user trust decision before it is admitted into a
/// group member's device roster. Persisted so a pending request survives restart.
class PendingSiblingDevice {
  final String groupId;
  final String memberPeerId;
  final String deviceId;
  final String transportPeerId;
  final String deviceSigningPublicKey;
  final String? mlKemPublicKey;
  final String? keyPackageId;

  /// The account signing key the announce's audit was verified against (the
  /// trust anchor admission re-checks). Persisted so a later verify-and-admit
  /// does not have to re-derive it.
  final String verifiedAccountSigningPublicKey;
  final DateTime announcedAt;

  const PendingSiblingDevice({
    required this.groupId,
    required this.memberPeerId,
    required this.deviceId,
    required this.transportPeerId,
    required this.deviceSigningPublicKey,
    this.mlKemPublicKey,
    this.keyPackageId,
    required this.verifiedAccountSigningPublicKey,
    required this.announcedAt,
  });

  Map<String, Object?> toMap() => {
    'group_id': groupId,
    'member_peer_id': memberPeerId,
    'device_id': deviceId,
    'transport_peer_id': transportPeerId,
    'device_signing_public_key': deviceSigningPublicKey,
    'ml_kem_public_key': mlKemPublicKey,
    'key_package_id': keyPackageId,
    'verified_account_signing_public_key': verifiedAccountSigningPublicKey,
    'announced_at': announcedAt.toUtc().toIso8601String(),
  };

  static PendingSiblingDevice fromMap(Map<String, Object?> map) =>
      PendingSiblingDevice(
        groupId: map['group_id'] as String,
        memberPeerId: map['member_peer_id'] as String,
        deviceId: map['device_id'] as String,
        transportPeerId: map['transport_peer_id'] as String,
        deviceSigningPublicKey: map['device_signing_public_key'] as String,
        mlKemPublicKey: map['ml_kem_public_key'] as String?,
        keyPackageId: map['key_package_id'] as String?,
        verifiedAccountSigningPublicKey:
            map['verified_account_signing_public_key'] as String,
        announcedAt:
            DateTime.tryParse(map['announced_at'] as String? ?? '')?.toUtc() ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );

  /// Stable id for (group, member, device).
  String get id => '$groupId:$memberPeerId:$deviceId';
}
