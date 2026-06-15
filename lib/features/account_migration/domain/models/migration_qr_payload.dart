import 'dart:collection';
import 'dart:convert';

const accountMigrationPairingQrKind = 'account_migration_pairing';
const currentAccountMigrationPairingQrVersion = 1;

class MigrationQrPayload {
  final String sessionId;
  final DateTime createdAt;
  final DateTime expiresAt;
  final String newPhoneEphemeralPublicKey;
  final String? channelNonce;

  MigrationQrPayload({
    required this.sessionId,
    required this.createdAt,
    required this.expiresAt,
    required this.newPhoneEphemeralPublicKey,
    this.channelNonce,
  }) {
    _requireNonEmpty(sessionId, 'sessionId');
    _requireNonEmpty(newPhoneEphemeralPublicKey, 'newPhoneEphemeralPublicKey');
    if (channelNonce != null) {
      _requireNonEmpty(channelNonce!, 'channelNonce');
    }
  }

  factory MigrationQrPayload.fromJson(Map<String, dynamic> json) {
    return MigrationQrPayload(
      sessionId: json['sessionId'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
      expiresAt: DateTime.parse(json['expiresAt'] as String).toUtc(),
      newPhoneEphemeralPublicKey: json['newPhoneEphemeralPublicKey'] as String,
      channelNonce: json['channelNonce'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (channelNonce != null) 'channelNonce': channelNonce,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'expiresAt': expiresAt.toUtc().toIso8601String(),
      'kind': accountMigrationPairingQrKind,
      'newPhoneEphemeralPublicKey': newPhoneEphemeralPublicKey,
      'sessionId': sessionId,
      'version': currentAccountMigrationPairingQrVersion,
    };
  }

  String toJsonString() {
    return jsonEncode(SplayTreeMap<String, dynamic>.from(toJson()));
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is MigrationQrPayload &&
            other.sessionId == sessionId &&
            other.createdAt == createdAt &&
            other.expiresAt == expiresAt &&
            other.newPhoneEphemeralPublicKey == newPhoneEphemeralPublicKey &&
            other.channelNonce == channelNonce;
  }

  @override
  int get hashCode {
    return Object.hash(
      sessionId,
      createdAt,
      expiresAt,
      newPhoneEphemeralPublicKey,
      channelNonce,
    );
  }
}

class MigrationPendingPairingSession {
  final String sessionId;
  final DateTime createdAt;
  final DateTime expiresAt;
  final String newPhoneEphemeralPublicKey;
  final String newPhoneEphemeralSecretKey;

  MigrationPendingPairingSession({
    required this.sessionId,
    required this.createdAt,
    required this.expiresAt,
    required this.newPhoneEphemeralPublicKey,
    required this.newPhoneEphemeralSecretKey,
  }) {
    _requireNonEmpty(sessionId, 'sessionId');
    _requireNonEmpty(newPhoneEphemeralPublicKey, 'newPhoneEphemeralPublicKey');
    _requireNonEmpty(newPhoneEphemeralSecretKey, 'newPhoneEphemeralSecretKey');
  }

  factory MigrationPendingPairingSession.fromJson(Map<String, dynamic> json) {
    return MigrationPendingPairingSession(
      sessionId: json['sessionId'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
      expiresAt: DateTime.parse(json['expiresAt'] as String).toUtc(),
      newPhoneEphemeralPublicKey: json['newPhoneEphemeralPublicKey'] as String,
      newPhoneEphemeralSecretKey: json['newPhoneEphemeralSecretKey'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sessionId': sessionId,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'expiresAt': expiresAt.toUtc().toIso8601String(),
      'newPhoneEphemeralPublicKey': newPhoneEphemeralPublicKey,
      'newPhoneEphemeralSecretKey': newPhoneEphemeralSecretKey,
    };
  }
}

class MigrationConsumedPairingSession {
  final String sessionId;
  final DateTime consumedAt;
  final DateTime qrCreatedAt;
  final DateTime qrExpiresAt;
  final String newPhoneEphemeralPublicKey;

  MigrationConsumedPairingSession({
    required this.sessionId,
    required this.consumedAt,
    required this.qrCreatedAt,
    required this.qrExpiresAt,
    required this.newPhoneEphemeralPublicKey,
  }) {
    _requireNonEmpty(sessionId, 'sessionId');
    _requireNonEmpty(newPhoneEphemeralPublicKey, 'newPhoneEphemeralPublicKey');
  }

  factory MigrationConsumedPairingSession.fromJson(Map<String, dynamic> json) {
    return MigrationConsumedPairingSession(
      sessionId: json['sessionId'] as String,
      consumedAt: DateTime.parse(json['consumedAt'] as String).toUtc(),
      qrCreatedAt: DateTime.parse(json['qrCreatedAt'] as String).toUtc(),
      qrExpiresAt: DateTime.parse(json['qrExpiresAt'] as String).toUtc(),
      newPhoneEphemeralPublicKey: json['newPhoneEphemeralPublicKey'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sessionId': sessionId,
      'consumedAt': consumedAt.toUtc().toIso8601String(),
      'qrCreatedAt': qrCreatedAt.toUtc().toIso8601String(),
      'qrExpiresAt': qrExpiresAt.toUtc().toIso8601String(),
      'newPhoneEphemeralPublicKey': newPhoneEphemeralPublicKey,
    };
  }
}

void _requireNonEmpty(String value, String fieldName) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, fieldName, 'must not be empty');
  }
}
