/// Model representing a contact added via QR code scanning.
///
/// Contains the peer information extracted from a scanned QR payload.
class ContactModel {
  /// The peer's unique identifier (ns field from QR).
  final String peerId;

  /// Base64-encoded public key (pk field from QR).
  final String publicKey;

  /// Rendezvous multiaddr for connecting (rv field from QR).
  final String rendezvous;

  /// The contact's username.
  final String username;

  /// Base64-encoded signature for verification.
  final String signature;

  /// ISO-8601 timestamp when the contact was scanned/added.
  final String scannedAt;

  /// Optional path to a custom avatar image.
  final String? avatarPath;

  /// ISO-8601 timestamp of the avatar version, for change detection.
  final String? avatarVersion;

  /// Base64-encoded ML-KEM-768 public key for post-quantum encryption.
  final String? mlKemPublicKey;

  /// Whether this contact is archived (hidden from active list).
  final bool isArchived;

  /// ISO-8601 timestamp when the contact was archived, null if active.
  final String? archivedAt;

  /// Whether this contact is blocked.
  final bool isBlocked;

  /// ISO-8601 timestamp when the contact was blocked, null if not blocked.
  final String? blockedAt;

  const ContactModel({
    required this.peerId,
    required this.publicKey,
    required this.rendezvous,
    required this.username,
    required this.signature,
    required this.scannedAt,
    this.avatarPath,
    this.avatarVersion,
    this.mlKemPublicKey,
    this.isArchived = false,
    this.archivedAt,
    this.isBlocked = false,
    this.blockedAt,
  });

  /// Creates a ContactModel from a QR payload JSON map.
  ///
  /// The QR payload contains: pk, ns, rv, ts, sig, un
  factory ContactModel.fromQRPayload(Map<String, dynamic> json) {
    return ContactModel(
      peerId: json['ns'] as String,
      publicKey: json['pk'] as String,
      rendezvous: json['rv'] as String,
      username: json['un'] as String? ?? 'Unknown',
      signature: json['sig'] as String,
      scannedAt: DateTime.now().toUtc().toIso8601String(),
      mlKemPublicKey: json['mlkem'] as String?,
    );
  }

  /// Creates a ContactModel from a database row.
  factory ContactModel.fromMap(Map<String, dynamic> map) {
    return ContactModel(
      peerId: map['peer_id'] as String,
      publicKey: map['public_key'] as String,
      rendezvous: map['rendezvous'] as String,
      username: map['username'] as String,
      signature: map['signature'] as String,
      scannedAt: map['scanned_at'] as String,
      avatarPath: map['avatar_path'] as String?,
      avatarVersion: map['avatar_version'] as String?,
      mlKemPublicKey: map['ml_kem_public_key'] as String?,
      isArchived: (map['is_archived'] as int? ?? 0) == 1,
      archivedAt: map['archived_at'] as String?,
      isBlocked: (map['is_blocked'] as int? ?? 0) == 1,
      blockedAt: map['blocked_at'] as String?,
    );
  }

  /// Converts the model to a database row map.
  Map<String, dynamic> toMap() {
    return {
      'peer_id': peerId,
      'public_key': publicKey,
      'rendezvous': rendezvous,
      'username': username,
      'signature': signature,
      'scanned_at': scannedAt,
      'avatar_path': avatarPath,
      'avatar_version': avatarVersion,
      'ml_kem_public_key': mlKemPublicKey,
      'is_archived': isArchived ? 1 : 0,
      'archived_at': archivedAt,
      'is_blocked': isBlocked ? 1 : 0,
      'blocked_at': blockedAt,
    };
  }

  /// Creates a copy with updated fields.
  ContactModel copyWith({
    String? peerId,
    String? publicKey,
    String? rendezvous,
    String? username,
    String? signature,
    String? scannedAt,
    String? avatarPath,
    String? avatarVersion,
    String? mlKemPublicKey,
    bool? isArchived,
    String? archivedAt,
    bool clearArchivedAt = false,
    bool? isBlocked,
    String? blockedAt,
    bool clearBlockedAt = false,
  }) {
    return ContactModel(
      peerId: peerId ?? this.peerId,
      publicKey: publicKey ?? this.publicKey,
      rendezvous: rendezvous ?? this.rendezvous,
      username: username ?? this.username,
      signature: signature ?? this.signature,
      scannedAt: scannedAt ?? this.scannedAt,
      avatarPath: avatarPath ?? this.avatarPath,
      avatarVersion: avatarVersion ?? this.avatarVersion,
      mlKemPublicKey: mlKemPublicKey ?? this.mlKemPublicKey,
      isArchived: isArchived ?? this.isArchived,
      archivedAt: clearArchivedAt ? null : (archivedAt ?? this.archivedAt),
      isBlocked: isBlocked ?? this.isBlocked,
      blockedAt: clearBlockedAt ? null : (blockedAt ?? this.blockedAt),
    );
  }

  @override
  String toString() {
    return 'ContactModel(peerId: ${peerId.substring(0, 10)}..., username: $username)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ContactModel && other.peerId == peerId;
  }

  @override
  int get hashCode => peerId.hashCode;
}
