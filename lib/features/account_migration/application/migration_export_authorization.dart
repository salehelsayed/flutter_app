import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_qr_payload.dart';
import 'package:flutter_app/features/account_migration/domain/repositories/migration_pairing_session_repository.dart';

enum MigrationExportAuthorizationResult { authorized, alreadyConsumed, expired }

class MigrationExportAuthorization {
  final String sessionId;
  final String newPhoneEphemeralPublicKey;
  final DateTime authorizedAt;

  const MigrationExportAuthorization({
    required this.sessionId,
    required this.newPhoneEphemeralPublicKey,
    required this.authorizedAt,
  });

  bool authorizes({
    required String sessionId,
    required String newPhoneEphemeralPublicKey,
  }) {
    return this.sessionId == sessionId &&
        this.newPhoneEphemeralPublicKey == newPhoneEphemeralPublicKey;
  }
}

Future<(MigrationExportAuthorizationResult, MigrationExportAuthorization?)>
authorizeMigrationExport({
  required MigrationPairingSessionRepository repository,
  required MigrationQrPayload payload,
  required DateTime authorizedAt,
}) async {
  final currentTime = authorizedAt.toUtc();
  if (!payload.expiresAt.isAfter(currentTime)) {
    return (MigrationExportAuthorizationResult.expired, null);
  }

  final consumeResult = await repository.consumeSession(
    payload: payload,
    consumedAt: currentTime,
  );
  if (consumeResult == MigrationPairingSessionConsumeResult.alreadyConsumed) {
    return (MigrationExportAuthorizationResult.alreadyConsumed, null);
  }

  return (
    MigrationExportAuthorizationResult.authorized,
    MigrationExportAuthorization(
      sessionId: payload.sessionId,
      newPhoneEphemeralPublicKey: payload.newPhoneEphemeralPublicKey,
      authorizedAt: currentTime,
    ),
  );
}

class AuthenticatedMigrationChannelTranscript {
  final String sessionId;
  final String newPhoneEphemeralPublicKey;
  final String oldPhonePeerId;
  final String authenticatedChannelBinding;
  final String authorizationNonce;

  AuthenticatedMigrationChannelTranscript({
    required this.sessionId,
    required this.newPhoneEphemeralPublicKey,
    required this.oldPhonePeerId,
    required this.authenticatedChannelBinding,
    required this.authorizationNonce,
  }) {
    _requireNonEmpty(sessionId, 'sessionId');
    _requireNonEmpty(newPhoneEphemeralPublicKey, 'newPhoneEphemeralPublicKey');
    _requireNonEmpty(oldPhonePeerId, 'oldPhonePeerId');
    _requireNonEmpty(
      authenticatedChannelBinding,
      'authenticatedChannelBinding',
    );
    _requireNonEmpty(authorizationNonce, 'authorizationNonce');
  }

  factory AuthenticatedMigrationChannelTranscript.fromJson(
    Map<String, dynamic> json,
  ) {
    return AuthenticatedMigrationChannelTranscript(
      sessionId: json['sessionId'] as String,
      newPhoneEphemeralPublicKey: json['newPhoneEphemeralPublicKey'] as String,
      oldPhonePeerId: json['oldPhonePeerId'] as String,
      authenticatedChannelBinding:
          json['authenticatedChannelBinding'] as String,
      authorizationNonce: json['authorizationNonce'] as String,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'authenticatedChannelBinding': authenticatedChannelBinding,
      'authorizationNonce': authorizationNonce,
      'newPhoneEphemeralPublicKey': newPhoneEphemeralPublicKey,
      'oldPhonePeerId': oldPhonePeerId,
      'sessionId': sessionId,
    };
  }

  String toCanonicalJson() {
    return jsonEncode(SplayTreeMap<String, Object?>.from(toJson()));
  }
}

String deriveMigrationConfirmationCode(
  AuthenticatedMigrationChannelTranscript transcript,
) {
  final bytes = sha256.convert(utf8.encode(transcript.toCanonicalJson())).bytes;
  final value =
      ((bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3]) %
      1000000;
  return value.toString().padLeft(6, '0');
}

void _requireNonEmpty(String value, String fieldName) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, fieldName, 'must not be empty');
  }
}
