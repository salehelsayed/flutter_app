import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/database/helpers/group_event_log_db_helpers.dart';

const authenticatedGroupAuthorityPurpose =
    'authenticated_group_authority_history_v1';
const authenticatedGroupAuthorityVersion = 1;
const authenticatedGroupAuthoritySigningDomain =
    'mknoon/authenticated-group-authority-history/v1';

const protectedGroupAuthorityGenesisEventType = 'protected_authority_genesis';
const protectedGroupAuthorityPreparedEventType = 'protected_authority_prepared';
const protectedGroupAuthorityCompleteEventType = 'protected_authority_complete';

enum AuthenticatedGroupAuthorityPhase {
  genesis('g', protectedGroupAuthorityGenesisEventType),
  prepared('p', protectedGroupAuthorityPreparedEventType),
  complete('c', protectedGroupAuthorityCompleteEventType);

  const AuthenticatedGroupAuthorityPhase(this.sourcePrefix, this.eventType);

  final String sourcePrefix;
  final String eventType;
}

typedef LoadAuthenticatedGroupAuthorityProof =
    Future<AuthenticatedGroupAuthorityProof?> Function({
      required String groupId,
      required AuthenticatedGroupAuthorityPhase phase,
      required String eventId,
    });

typedef AppendAuthenticatedGroupAuthorityProof =
    Future<void> Function({
      required AuthenticatedGroupAuthorityPhase phase,
      required AuthenticatedGroupAuthorityProof proof,
    });

typedef VerifyAuthenticatedGroupAuthorityProof =
    Future<bool> Function({
      required String publicKey,
      required String data,
      required String signature,
    });

typedef LoadGroupAuthorityEventLogExactRow =
    Future<Map<String, Object?>?> Function({
      required String groupId,
      required String sourceEventId,
    });

typedef LoadGroupAuthorityEventLogPageRows =
    Future<List<Map<String, Object?>>> Function({
      required String groupId,
      required String eventType,
      String? afterSourceTimestamp,
      String? afterSourceEventId,
      String? throughSourceTimestamp,
      required int limit,
    });

/// Secret-free, account-signed authority version retained after relay ACK.
///
/// [authorityData] contains a bootstrap roster/config snapshot or a protected
/// control descriptor. Key and encrypted-envelope bytes are represented only
/// by SHA-256 digests.
class AuthenticatedGroupAuthorityProof {
  const AuthenticatedGroupAuthorityProof({
    required this.eventId,
    required this.groupId,
    required this.eventAt,
    required this.keyEpoch,
    required this.control,
    required this.actorAccountPeerId,
    required this.actorAccountPublicKey,
    required this.senderTransportPeerId,
    required this.senderTransportPublicKey,
    required this.authorityData,
    required this.signature,
  });

  final String eventId;
  final String groupId;
  final DateTime eventAt;
  final int keyEpoch;
  final String control;
  final String actorAccountPeerId;
  final String actorAccountPublicKey;
  final String senderTransportPeerId;
  final String senderTransportPublicKey;
  final Map<String, Object?> authorityData;
  final String signature;

  Map<String, Object?> unsignedBody() => <String, Object?>{
    'purpose': authenticatedGroupAuthorityPurpose,
    'version': authenticatedGroupAuthorityVersion,
    'eventId': eventId,
    'groupId': groupId,
    'eventAt': fixedGroupAuthorityUtc(eventAt),
    'keyEpoch': keyEpoch,
    'control': control,
    'actorAccountPeerId': actorAccountPeerId,
    'actorAccountPublicKey': actorAccountPublicKey,
    'senderTransportPeerId': senderTransportPeerId,
    'senderTransportPublicKey': senderTransportPublicKey,
    'authorityData': authorityData,
  };

  String canonicalSignedPayload() =>
      '$authenticatedGroupAuthoritySigningDomain\n'
      '${canonicalizeGroupEventLogPayload(unsignedBody())}';

  Map<String, Object?> toMap() => <String, Object?>{
    'body': unsignedBody(),
    'signature': signature,
  };

  AuthenticatedGroupAuthorityProof withSignature(String value) =>
      AuthenticatedGroupAuthorityProof(
        eventId: eventId,
        groupId: groupId,
        eventAt: eventAt,
        keyEpoch: keyEpoch,
        control: control,
        actorAccountPeerId: actorAccountPeerId,
        actorAccountPublicKey: actorAccountPublicKey,
        senderTransportPeerId: senderTransportPeerId,
        senderTransportPublicKey: senderTransportPublicKey,
        authorityData: authorityData,
        signature: value,
      );

  bool sameUnsigned(AuthenticatedGroupAuthorityProof other) =>
      canonicalSignedPayload() == other.canonicalSignedPayload();

  static AuthenticatedGroupAuthorityProof? tryParse(Object? raw) {
    try {
      if (raw is! Map || raw.length != 2) return null;
      final map = Map<String, dynamic>.from(raw);
      final bodyRaw = map['body'];
      final signature = _strictString(map['signature']);
      if (bodyRaw is! Map || signature == null) return null;
      final body = Map<String, dynamic>.from(bodyRaw);
      if (body.length != _authorityProofBodyKeys.length ||
          !body.keys.toSet().containsAll(_authorityProofBodyKeys) ||
          body['purpose'] != authenticatedGroupAuthorityPurpose ||
          body['version'] != authenticatedGroupAuthorityVersion) {
        return null;
      }
      final eventId = _strictString(body['eventId']);
      final groupId = _strictString(body['groupId']);
      final eventAt = parseFixedGroupAuthorityUtc(body['eventAt']);
      final keyEpoch = body['keyEpoch'];
      final control = _strictString(body['control']);
      final actorAccountPeerId = _strictString(body['actorAccountPeerId']);
      final actorAccountPublicKey = _strictString(
        body['actorAccountPublicKey'],
      );
      final senderTransportPeerId = _strictString(
        body['senderTransportPeerId'],
      );
      final senderTransportPublicKey = _strictString(
        body['senderTransportPublicKey'],
      );
      final authorityDataRaw = body['authorityData'];
      if (eventId == null ||
          groupId == null ||
          eventAt == null ||
          keyEpoch is! int ||
          keyEpoch <= 0 ||
          control == null ||
          actorAccountPeerId == null ||
          actorAccountPublicKey == null ||
          senderTransportPeerId == null ||
          senderTransportPublicKey == null ||
          authorityDataRaw is! Map) {
        return null;
      }
      final authorityData = Map<String, Object?>.from(authorityDataRaw);
      // Reject values that cannot participate in the deterministic signed form.
      canonicalizeGroupEventLogPayload(authorityData);
      return AuthenticatedGroupAuthorityProof(
        eventId: eventId,
        groupId: groupId,
        eventAt: eventAt,
        keyEpoch: keyEpoch,
        control: control,
        actorAccountPeerId: actorAccountPeerId,
        actorAccountPublicKey: actorAccountPublicKey,
        senderTransportPeerId: senderTransportPeerId,
        senderTransportPublicKey: senderTransportPublicKey,
        authorityData: authorityData,
        signature: signature,
      );
    } catch (_) {
      return null;
    }
  }
}

const _authorityProofBodyKeys = <String>{
  'purpose',
  'version',
  'eventId',
  'groupId',
  'eventAt',
  'keyEpoch',
  'control',
  'actorAccountPeerId',
  'actorAccountPublicKey',
  'senderTransportPeerId',
  'senderTransportPublicKey',
  'authorityData',
};

String fixedGroupAuthorityUtc(DateTime value) {
  final utc = value.toUtc();
  String two(int part) => part.toString().padLeft(2, '0');
  final micros =
      utc.millisecond * Duration.microsecondsPerMillisecond + utc.microsecond;
  return '${utc.year.toString().padLeft(4, '0')}-'
      '${two(utc.month)}-${two(utc.day)}T${two(utc.hour)}:'
      '${two(utc.minute)}:${two(utc.second)}.'
      '${micros.toString().padLeft(6, '0')}Z';
}

DateTime? parseFixedGroupAuthorityUtc(Object? value) {
  final raw = _strictString(value);
  if (raw == null ||
      !RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$').hasMatch(raw)) {
    return null;
  }
  final parsed = DateTime.tryParse(raw);
  return parsed != null && parsed.isUtc ? parsed : null;
}

String authenticatedGroupAuthoritySourceEventId(
  AuthenticatedGroupAuthorityPhase phase,
  String eventId,
) {
  final encoded = base64Url.encode(utf8.encode(eventId)).replaceAll('=', '');
  return 'pga1:${phase.sourcePrefix}:$encoded';
}

String groupAuthoritySha256(String value) =>
    sha256.convert(utf8.encode(value)).toString();

/// Produces the only protected-control bytes permitted in durable history.
Map<String, Object?> secretFreeProtectedAuthorityData({
  required String control,
  required Map<String, dynamic> replayData,
}) {
  if (control == 'group_key_update') {
    final encryptedKey = replayData['encryptedKey'];
    final content = replayData['content'];
    return <String, Object?>{
      'groupId': replayData['groupId'],
      'keyGeneration': replayData['keyGeneration'],
      if (encryptedKey is String)
        'encryptedKeyHash': groupAuthoritySha256(encryptedKey),
      'from': replayData['from'],
      'to': replayData['to'],
      if (content is String) 'contentHash': groupAuthoritySha256(content),
      'timestamp': replayData['timestamp'],
    };
  }
  return <String, Object?>{
    'groupId': replayData['groupId'],
    'senderId': replayData['senderId'],
    'senderUsername': replayData['senderUsername'],
    if (replayData['senderDeviceId'] != null)
      'senderDeviceId': replayData['senderDeviceId'],
    if (replayData['transportPeerId'] != null)
      'transportPeerId': replayData['transportPeerId'],
    'text': replayData['text'],
    'timestamp': replayData['timestamp'],
    if (replayData['messageId'] != null) 'messageId': replayData['messageId'],
  };
}

Map<String, Object?> authenticatedGroupAuthorityFactPayload(
  AuthenticatedGroupAuthorityProof proof,
) => <String, Object?>{'proof': proof.toMap()};

AuthenticatedGroupAuthorityProof? proofFromGroupAuthorityEventLogRow(
  Map<String, Object?> row,
) {
  final canonical = row['canonical_payload'];
  if (canonical is! String) return null;
  final decoded = jsonDecode(canonical);
  if (decoded is! Map || decoded['proof'] is! Map) return null;
  return AuthenticatedGroupAuthorityProof.tryParse(decoded['proof']);
}

Future<AuthenticatedGroupAuthorityProof?>
loadAuthenticatedGroupAuthorityProofFromEventLog({
  required LoadGroupAuthorityEventLogExactRow loadRow,
  required String groupId,
  required AuthenticatedGroupAuthorityPhase phase,
  required VerifyAuthenticatedGroupAuthorityProof verify,
  required String eventId,
}) async {
  final sourceEventId = authenticatedGroupAuthoritySourceEventId(
    phase,
    eventId,
  );
  final row = await loadRow(groupId: groupId, sourceEventId: sourceEventId);
  if (row == null) return null;
  final proof = proofFromGroupAuthorityEventLogRow(row);
  if (row['event_type'] != phase.eventType ||
      proof == null ||
      proof.groupId != groupId ||
      proof.eventId != eventId ||
      row['source_peer_id'] != proof.actorAccountPeerId ||
      row['source_timestamp'] != fixedGroupAuthorityUtc(proof.eventAt) ||
      !await verify(
        publicKey: proof.actorAccountPublicKey,
        data: proof.canonicalSignedPayload(),
        signature: proof.signature,
      )) {
    throw GroupEventLogTamperException(
      'invalid authenticated authority history fact',
    );
  }
  return proof;
}

/// Loads at most [limit] authenticated facts without an unbounded table scan.
Future<List<AuthenticatedGroupAuthorityProof>>
loadAuthenticatedGroupAuthorityProofPage({
  required LoadGroupAuthorityEventLogPageRows loadRows,
  required String groupId,
  required AuthenticatedGroupAuthorityPhase phase,
  required VerifyAuthenticatedGroupAuthorityProof verify,
  String? afterSourceTimestamp,
  String? afterSourceEventId,
  String? throughSourceTimestamp,
  int limit = 100,
}) async {
  if (limit < 1 || limit > 200) {
    throw RangeError.range(limit, 1, 200, 'limit');
  }
  final rows = await loadRows(
    groupId: groupId,
    eventType: phase.eventType,
    afterSourceTimestamp: afterSourceTimestamp,
    afterSourceEventId: afterSourceEventId,
    throughSourceTimestamp: throughSourceTimestamp,
    limit: limit,
  );
  final result = <AuthenticatedGroupAuthorityProof>[];
  for (final row in rows) {
    final proof = proofFromGroupAuthorityEventLogRow(row);
    if (proof == null ||
        proof.groupId != groupId ||
        row['source_peer_id'] != proof.actorAccountPeerId ||
        row['source_timestamp'] != fixedGroupAuthorityUtc(proof.eventAt) ||
        !await verify(
          publicKey: proof.actorAccountPublicKey,
          data: proof.canonicalSignedPayload(),
          signature: proof.signature,
        )) {
      throw GroupEventLogTamperException(
        'invalid authenticated authority history page fact',
      );
    }
    result.add(proof);
  }
  return result;
}

Future<AuthenticatedGroupAuthorityProof?> loadAuthenticatedAuthorityVersion({
  required LoadAuthenticatedGroupAuthorityProof load,
  required VerifyAuthenticatedGroupAuthorityProof verify,
  required String groupId,
  required DateTime eventAt,
  required String eventId,
  required int keyEpoch,
}) async {
  for (final phase in const <AuthenticatedGroupAuthorityPhase>[
    AuthenticatedGroupAuthorityPhase.genesis,
    AuthenticatedGroupAuthorityPhase.complete,
  ]) {
    final proof = await load(groupId: groupId, phase: phase, eventId: eventId);
    if (proof == null) continue;
    if (proof.groupId != groupId ||
        proof.eventId != eventId ||
        proof.keyEpoch != keyEpoch ||
        proof.eventAt.toUtc() != eventAt.toUtc()) {
      return null;
    }
    if (await verify(
      publicKey: proof.actorAccountPublicKey,
      data: proof.canonicalSignedPayload(),
      signature: proof.signature,
    )) {
      return proof;
    }
    return null;
  }
  return null;
}

String? _strictString(Object? value) {
  if (value is! String || value.isEmpty || value.trim() != value) return null;
  return value;
}
