import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';

/// Status of a contact request.
enum ContactRequestStatus {
  /// Request is waiting for user action.
  pending,

  /// Request was accepted, contact added.
  accepted,

  /// Request was declined by user.
  declined,
}

/// Model representing an incoming contact request received via P2P.
///
/// Contains the peer information from a contact_request message.
class ContactRequestModel {
  /// The peer's unique identifier (ns field from payload).
  final String peerId;

  /// Base64-encoded public key (pk field from payload).
  final String publicKey;

  /// Rendezvous multiaddr for connecting (rv field from payload).
  final String rendezvous;

  /// The sender's username.
  final String username;

  /// Base64-encoded signature for verification.
  final String signature;

  /// ISO-8601 timestamp when the request was received.
  final String receivedAt;

  /// Current status of the request.
  final ContactRequestStatus status;

  const ContactRequestModel({
    required this.peerId,
    required this.publicKey,
    required this.rendezvous,
    required this.username,
    required this.signature,
    required this.receivedAt,
    this.status = ContactRequestStatus.pending,
  });

  /// Creates a ContactRequestModel from a P2P message payload.
  ///
  /// The payload contains: pk, ns, rv, ts, sig, un
  factory ContactRequestModel.fromP2PPayload(Map<String, dynamic> payload) {
    return ContactRequestModel(
      peerId: payload['ns'] as String,
      publicKey: payload['pk'] as String,
      rendezvous: payload['rv'] as String,
      username: payload['un'] as String? ?? 'Unknown',
      signature: payload['sig'] as String,
      receivedAt: DateTime.now().toUtc().toIso8601String(),
      status: ContactRequestStatus.pending,
    );
  }

  /// Creates a ContactRequestModel from a database row.
  factory ContactRequestModel.fromMap(Map<String, dynamic> map) {
    return ContactRequestModel(
      peerId: map['peer_id'] as String,
      publicKey: map['public_key'] as String,
      rendezvous: map['rendezvous'] as String,
      username: map['username'] as String,
      signature: map['signature'] as String,
      receivedAt: map['received_at'] as String,
      status: _statusFromString(map['status'] as String? ?? 'pending'),
    );
  }

  static ContactRequestStatus _statusFromString(String status) {
    switch (status) {
      case 'accepted':
        return ContactRequestStatus.accepted;
      case 'declined':
        return ContactRequestStatus.declined;
      default:
        return ContactRequestStatus.pending;
    }
  }

  static String _statusToString(ContactRequestStatus status) {
    switch (status) {
      case ContactRequestStatus.accepted:
        return 'accepted';
      case ContactRequestStatus.declined:
        return 'declined';
      case ContactRequestStatus.pending:
        return 'pending';
    }
  }

  /// Converts the model to a database row map.
  Map<String, dynamic> toMap() {
    return {
      'peer_id': peerId,
      'public_key': publicKey,
      'rendezvous': rendezvous,
      'username': username,
      'signature': signature,
      'received_at': receivedAt,
      'status': _statusToString(status),
    };
  }

  /// Converts this request to a ContactModel when accepted.
  ContactModel toContactModel() {
    return ContactModel(
      peerId: peerId,
      publicKey: publicKey,
      rendezvous: rendezvous,
      username: username,
      signature: signature,
      scannedAt: DateTime.now().toUtc().toIso8601String(),
    );
  }

  /// Creates a copy with updated fields.
  ContactRequestModel copyWith({
    String? peerId,
    String? publicKey,
    String? rendezvous,
    String? username,
    String? signature,
    String? receivedAt,
    ContactRequestStatus? status,
  }) {
    return ContactRequestModel(
      peerId: peerId ?? this.peerId,
      publicKey: publicKey ?? this.publicKey,
      rendezvous: rendezvous ?? this.rendezvous,
      username: username ?? this.username,
      signature: signature ?? this.signature,
      receivedAt: receivedAt ?? this.receivedAt,
      status: status ?? this.status,
    );
  }

  @override
  String toString() {
    final prefix = peerId.length > 10 ? peerId.substring(0, 10) : peerId;
    return 'ContactRequestModel(peerId: $prefix..., username: $username, status: $status)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ContactRequestModel && other.peerId == peerId;
  }

  @override
  int get hashCode => peerId.hashCode;
}
