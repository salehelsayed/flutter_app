import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_qr_payload.dart';
import 'package:flutter_app/features/account_migration/domain/repositories/migration_pairing_session_repository.dart';
import 'package:uuid/uuid.dart';

enum BuildMigrationQrPayloadResult { success, keygenFailed, persistenceFailed }

enum MigrationQrParseResult {
  success,
  invalidJson,
  wrongKind,
  unsupportedVersion,
  missingFields,
  malformedTimestamp,
  expired,
  futureTimestamp,
}

class MigrationQrBuildOutput {
  final MigrationQrPayload payload;
  final String qrJson;

  const MigrationQrBuildOutput({required this.payload, required this.qrJson});
}

Future<(BuildMigrationQrPayloadResult, MigrationQrBuildOutput?)>
buildMigrationQrPayload({
  required Bridge bridge,
  required MigrationPairingSessionRepository repository,
  String Function()? sessionIdProvider,
  DateTime Function()? now,
  Duration ttl = const Duration(minutes: 5),
  String? channelNonce,
}) async {
  final keygen = await callMlKemKeygen(bridge);
  if (keygen['ok'] != true) {
    return (BuildMigrationQrPayloadResult.keygenFailed, null);
  }

  final publicKey = keygen['publicKey'];
  final secretKey = keygen['secretKey'];
  if (publicKey is! String ||
      publicKey.trim().isEmpty ||
      secretKey is! String ||
      secretKey.trim().isEmpty) {
    return (BuildMigrationQrPayloadResult.keygenFailed, null);
  }

  final createdAt = (now ?? DateTime.now)().toUtc();
  final expiresAt = createdAt.add(ttl);
  final sessionId = (sessionIdProvider ?? const Uuid().v4)();

  final payload = MigrationQrPayload(
    sessionId: sessionId,
    createdAt: createdAt,
    expiresAt: expiresAt,
    newPhoneEphemeralPublicKey: publicKey.trim(),
    channelNonce: channelNonce,
  );
  final pendingSession = MigrationPendingPairingSession(
    sessionId: sessionId,
    createdAt: createdAt,
    expiresAt: expiresAt,
    newPhoneEphemeralPublicKey: publicKey.trim(),
    newPhoneEphemeralSecretKey: secretKey.trim(),
  );

  try {
    await repository.savePendingNewPhoneSession(pendingSession);
  } catch (_) {
    return (BuildMigrationQrPayloadResult.persistenceFailed, null);
  }

  return (
    BuildMigrationQrPayloadResult.success,
    MigrationQrBuildOutput(payload: payload, qrJson: payload.toJsonString()),
  );
}

String deriveMigrationPairingConfirmationCode(MigrationQrPayload payload) {
  final bytes = sha256.convert(utf8.encode(payload.toJsonString())).bytes;
  final value =
      ((bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3]) %
      1000000;
  return value.toString().padLeft(6, '0');
}

(MigrationQrParseResult, MigrationQrPayload?) parseMigrationQrPayload({
  required String qrData,
  DateTime Function()? now,
  Duration maxFutureClockSkew = const Duration(minutes: 2),
}) {
  final Map<String, dynamic> decoded;
  try {
    final value = jsonDecode(qrData);
    if (value is! Map<String, dynamic>) {
      return (MigrationQrParseResult.invalidJson, null);
    }
    decoded = value;
  } catch (_) {
    return (MigrationQrParseResult.invalidJson, null);
  }

  final kind = decoded['kind'];
  if (kind != accountMigrationPairingQrKind) {
    return (MigrationQrParseResult.wrongKind, null);
  }

  final version = decoded['version'];
  if (version == null) {
    return (MigrationQrParseResult.missingFields, null);
  }
  if (version != currentAccountMigrationPairingQrVersion) {
    return (MigrationQrParseResult.unsupportedVersion, null);
  }

  const requiredStringFields = [
    'sessionId',
    'createdAt',
    'expiresAt',
    'newPhoneEphemeralPublicKey',
  ];
  for (final field in requiredStringFields) {
    final value = decoded[field];
    if (value is! String || value.trim().isEmpty) {
      return (MigrationQrParseResult.missingFields, null);
    }
  }
  final nonce = decoded['channelNonce'];
  if (nonce != null && (nonce is! String || nonce.trim().isEmpty)) {
    return (MigrationQrParseResult.missingFields, null);
  }

  final DateTime createdAt;
  final DateTime expiresAt;
  try {
    createdAt = DateTime.parse(decoded['createdAt'] as String).toUtc();
    expiresAt = DateTime.parse(decoded['expiresAt'] as String).toUtc();
  } catch (_) {
    return (MigrationQrParseResult.malformedTimestamp, null);
  }

  final currentTime = (now ?? DateTime.now)().toUtc();
  if (createdAt.isAfter(currentTime.add(maxFutureClockSkew))) {
    return (MigrationQrParseResult.futureTimestamp, null);
  }
  if (!expiresAt.isAfter(currentTime) || !expiresAt.isAfter(createdAt)) {
    return (MigrationQrParseResult.expired, null);
  }

  try {
    return (
      MigrationQrParseResult.success,
      MigrationQrPayload(
        sessionId: (decoded['sessionId'] as String).trim(),
        createdAt: createdAt,
        expiresAt: expiresAt,
        newPhoneEphemeralPublicKey:
            (decoded['newPhoneEphemeralPublicKey'] as String).trim(),
        channelNonce: nonce as String?,
      ),
    );
  } on ArgumentError {
    return (MigrationQrParseResult.missingFields, null);
  }
}
