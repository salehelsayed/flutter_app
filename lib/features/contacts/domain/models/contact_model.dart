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

  /// Base64-encoded ML-KEM-768 public key for post-quantum encryption.
  final String? mlKemPublicKey;

  const ContactModel({
    required this.peerId,
    required this.publicKey,
    required this.rendezvous,
    required this.username,
    required this.signature,
    required this.scannedAt,
    this.avatarPath,
    this.mlKemPublicKey,
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
      mlKemPublicKey: map['ml_kem_public_key'] as String?,
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
      'ml_kem_public_key': mlKemPublicKey,
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
    String? mlKemPublicKey,
  }) {
    return ContactModel(
      peerId: peerId ?? this.peerId,
      publicKey: publicKey ?? this.publicKey,
      rendezvous: rendezvous ?? this.rendezvous,
      username: username ?? this.username,
      signature: signature ?? this.signature,
      scannedAt: scannedAt ?? this.scannedAt,
      avatarPath: avatarPath ?? this.avatarPath,
      mlKemPublicKey: mlKemPublicKey ?? this.mlKemPublicKey,
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
