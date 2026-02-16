import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals;

/// Identity model representing a user's cryptographic identity.
///
/// This is an immutable data class that maps to the canonical IdentityJson
/// structure used across all layers of the application.
class IdentityModel {
  final String peerId;
  final String publicKey;
  final String privateKey;
  final String mnemonic12;
  final String? mlKemPublicKey;
  final String? mlKemSecretKey;
  final String username;
  final Uint8List? avatarBlob;
  final String createdAt;
  final String updatedAt;

  IdentityModel({
    required this.peerId,
    required this.publicKey,
    required this.privateKey,
    required this.mnemonic12,
    this.mlKemPublicKey,
    this.mlKemSecretKey,
    this.username = 'Username',
    this.avatarBlob,
    required this.createdAt,
    required this.updatedAt,
  });

  factory IdentityModel.fromJson(Map<String, dynamic> json) {
    return IdentityModel(
      peerId: json['peerId'] as String,
      publicKey: json['publicKey'] as String,
      privateKey: json['privateKey'] as String,
      mnemonic12: json['mnemonic12'] as String,
      mlKemPublicKey: json['mlKemPublicKey'] as String?,
      mlKemSecretKey: json['mlKemSecretKey'] as String?,
      username: json['username'] as String? ?? 'Username',
      createdAt: json['createdAt'] as String,
      updatedAt: json['updatedAt'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'peerId': peerId,
      'publicKey': publicKey,
      'privateKey': privateKey,
      'mnemonic12': mnemonic12,
      'mlKemPublicKey': mlKemPublicKey,
      'mlKemSecretKey': mlKemSecretKey,
      'username': username,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is IdentityModel &&
        other.peerId == peerId &&
        other.publicKey == publicKey &&
        other.privateKey == privateKey &&
        other.mnemonic12 == mnemonic12 &&
        other.mlKemPublicKey == mlKemPublicKey &&
        other.mlKemSecretKey == mlKemSecretKey &&
        other.username == username &&
        listEquals(other.avatarBlob, avatarBlob) &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode {
    return Object.hash(
      peerId,
      publicKey,
      privateKey,
      mnemonic12,
      mlKemPublicKey,
      mlKemSecretKey,
      username,
      avatarBlob != null ? Object.hashAll(avatarBlob!) : null,
      createdAt,
      updatedAt,
    );
  }

  @override
  String toString() {
    return 'IdentityModel(peerId: $peerId, createdAt: $createdAt, updatedAt: $updatedAt)';
  }
}
