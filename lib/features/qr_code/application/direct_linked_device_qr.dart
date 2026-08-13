import 'dart:collection';
import 'dart:convert';

import 'package:flutter_app/core/config/direct_linked_devices_flag.dart';
import 'package:flutter_app/core/config/multi_device_sync_flag.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/utils/key_conversion.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/identity/application/linked_installation_authority.dart';

/// Exact purpose string of the dedicated linked-device QR document.
const String directLinkedDeviceQrPurpose = 'direct_linked_device_binding';

/// Exact document version.
const int directLinkedDeviceQrVersion = 1;

/// Top-level envelope key.
const String _envelopeKey = 'mknoon';

/// Domain separator over the canonical body. Both signatures cover exactly
/// this string, so neither can be replayed against the legacy contact QR (a
/// flat, undomained document) or against any future mknoon payload.
const String directLinkedDeviceQrSigningDomain =
    'mknoon/direct-linked-device-binding/v1';

/// Maximum accepted age of an issued document — the existing bounded QR age.
const Duration directLinkedDeviceQrMaxAge = Duration(hours: 24);

/// Maximum accepted clock skew INTO the future.
///
/// Zero would make an issuer whose clock runs a few seconds fast unable to
/// pair at all; unbounded would let a forged far-future document stay valid
/// forever.
const Duration directLinkedDeviceQrMaxFutureSkew = Duration(minutes: 5);

/// Hard cap on the encoded document, in UTF-8 bytes.
///
/// The ML-KEM-768 public key dominates the payload (~1.6 KB base64), so this
/// bound is deliberately generous but finite: an unbounded document is a
/// memory and scan-time hazard, and anything near this size stops being
/// reliably scannable long before it stops parsing.
const int directLinkedDeviceQrMaxBytes = 4096;

const int _maxPeerIdLength = 128;
const int _maxPublicKeyLength = 128;
const int _maxDeviceIdLength = 128;
const int _maxMlKemPublicKeyLength = 2048;
const int _maxSignatureLength = 256;
const int _maxIssuedAtLength = 32;

const Set<String> _requiredBodyKeys = <String>{
  'accountPeerId',
  'accountPublicKey',
  'deviceId',
  'deviceMlKemPublicKey',
  'issuedAt',
  'transportPeerId',
  'transportPublicKey',
};

const Set<String> _requiredEnvelopeKeys = <String>{
  'accountSignature',
  'body',
  'purpose',
  'transportSignature',
  'version',
};

/// Outcome of building the dual-signed document.
enum BuildDirectLinkedDeviceQrResult {
  success,

  /// The direct selector is off, so new linked authority may not be authored.
  selectorDisabled,

  /// No ACTIVE linked credential exists on this installation.
  noLinkedAuthority,

  /// Identity, ML-KEM, or credential material is missing or inconsistent.
  invalidMaterial,

  /// One of the two bridge signatures failed.
  signingError,
}

/// Outcome of parsing and authenticating a scanned document.
enum ParseDirectLinkedDeviceQrResult {
  success,

  /// The direct selector is off, so scanning may not stage authority.
  selectorDisabled,

  /// Not JSON, wrong envelope/purpose/version, unexpected or missing keys,
  /// oversized, or a field that violates its length bound.
  ///
  /// A LEGACY contact QR also lands here: it has no `mknoon` envelope. That is
  /// the intended one-way relationship — the legacy parser likewise rejects
  /// this document for missing its own required flat fields, so neither
  /// producer can mutate the other's contact or ML-KEM state.
  malformed,

  /// Unparseable or non-UTC issued-at.
  invalidTimestamp,

  /// Older than [directLinkedDeviceQrMaxAge].
  expired,

  /// Further into the future than [directLinkedDeviceQrMaxFutureSkew].
  futureSkew,

  /// No contact with this account peer exists locally.
  unknownContact,

  /// The contact exists but is blocked.
  blockedContact,

  /// The stored contact account peer/public key is not byte-equal to the
  /// document's — stale document, rotated key, or a crossed account.
  contactKeyMismatch,

  /// A carried public key does not derive its claimed peer ID.
  peerDerivationMismatch,

  /// Either signature failed, or the two identities are not distinct.
  invalidSignature,

  /// The document describes this installation's own account.
  selfScan,
}

/// Result of authenticating the existing linked-device QR for the one
/// same-account, selected-group bootstrap entry point.
///
/// This is intentionally separate from [ParseDirectLinkedDeviceQrResult]: the
/// ordinary contact parser must keep returning `selfScan` before expensive
/// verification, while this narrow path must verify both signatures and time
/// bounds before it may author group authority.
enum ParseLinkedGroupBootstrapQrResult {
  success,
  selectorDisabled,
  multiDeviceDisabled,
  linkedScannerRefused,
  malformed,
  invalidTimestamp,
  expired,
  futureSkew,
  accountMismatch,
  peerDerivationMismatch,
  invalidSignature,
}

/// The authenticated contents of one linked-device QR document.
class DirectLinkedDeviceQrDocument {
  const DirectLinkedDeviceQrDocument({
    required this.accountPeerId,
    required this.accountPublicKey,
    required this.deviceId,
    required this.deviceMlKemPublicKey,
    required this.issuedAt,
    required this.transportPeerId,
    required this.transportPublicKey,
  });

  final String accountPeerId;
  final String accountPublicKey;
  final String deviceId;
  final String deviceMlKemPublicKey;
  final String issuedAt;
  final String transportPeerId;
  final String transportPublicKey;
}

/// Canonical, sorted-key serialization of the signed body.
///
/// Both signer and verifier build this from the SAME field set, so a document
/// carrying an extra field cannot smuggle unsigned data past verification —
/// the extra key is rejected as malformed before signature checking.
String canonicalDirectLinkedDeviceQrBody({
  required String accountPeerId,
  required String accountPublicKey,
  required String deviceId,
  required String deviceMlKemPublicKey,
  required String issuedAt,
  required String transportPeerId,
  required String transportPublicKey,
}) {
  final body = SplayTreeMap<String, Object?>.from(<String, Object?>{
    'accountPeerId': accountPeerId,
    'accountPublicKey': accountPublicKey,
    'deviceId': deviceId,
    'deviceMlKemPublicKey': deviceMlKemPublicKey,
    'issuedAt': issuedAt,
    'transportPeerId': transportPeerId,
    'transportPublicKey': transportPublicKey,
  });
  return jsonEncode(body);
}

/// The exact bytes both keys sign.
String directLinkedDeviceQrSignedPayload(String canonicalBody) =>
    '$directLinkedDeviceQrSigningDomain\n$canonicalBody';

/// Builds the dual-signed linked-device QR document.
///
/// Reachable only from the explicit linked setup/status route: it requires the
/// direct selector AND an ACTIVE linked credential, so an ordinary primary can
/// never author one.
///
/// The logical account key and the transport key sign INDEPENDENTLY. Either
/// signature alone proves only half of the claim — that an account vouches for
/// some device, or that a device exists — and a scanner that accepted one
/// would let an attacker bind their own transport to someone else's account,
/// or replay a real device under a forged account.
Future<(BuildDirectLinkedDeviceQrResult, String?)> buildDirectLinkedDeviceQr({
  required LinkedInstallationAuthoritySnapshot linkedAuthority,
  required String accountPeerId,
  required String accountPublicKey,
  required String accountPrivateKey,
  required String? deviceMlKemPublicKey,
  required Future<Map<String, dynamic>> Function(String data, String privateKey)
  callSign,
  DirectLinkedDeviceSelector selector = const DirectLinkedDeviceSelector(),
  DateTime Function()? now,
}) async {
  if (!selector.allowsLinkedDeviceAuthoring) {
    return (BuildDirectLinkedDeviceQrResult.selectorDisabled, null);
  }
  if (!linkedAuthority.isActiveLinkedSecondary) {
    return (BuildDirectLinkedDeviceQrResult.noLinkedAuthority, null);
  }
  final credential = linkedAuthority.credential;
  if (credential == null) {
    return (BuildDirectLinkedDeviceQrResult.noLinkedAuthority, null);
  }

  final normalizedAccountPeerId = accountPeerId.trim();
  final normalizedAccountPublicKey = accountPublicKey.trim();
  final normalizedMlKem = deviceMlKemPublicKey?.trim() ?? '';
  if (normalizedAccountPeerId.isEmpty ||
      normalizedAccountPublicKey.isEmpty ||
      accountPrivateKey.trim().isEmpty ||
      normalizedMlKem.isEmpty ||
      credential.accountPeerId != normalizedAccountPeerId ||
      credential.accountPublicKey != normalizedAccountPublicKey) {
    return (BuildDirectLinkedDeviceQrResult.invalidMaterial, null);
  }
  // Never publish a document whose own peers do not derive from its own keys.
  if (!ed25519PublicKeyMatchesPeerId(
        base64PublicKey: normalizedAccountPublicKey,
        claimedPeerId: normalizedAccountPeerId,
      ) ||
      !ed25519PublicKeyMatchesPeerId(
        base64PublicKey: credential.transportPublicKey,
        claimedPeerId: credential.transportPeerId,
      )) {
    return (BuildDirectLinkedDeviceQrResult.invalidMaterial, null);
  }

  final issuedAt = (now ?? DateTime.now)().toUtc().toIso8601String();
  final canonicalBody = canonicalDirectLinkedDeviceQrBody(
    accountPeerId: normalizedAccountPeerId,
    accountPublicKey: normalizedAccountPublicKey,
    deviceId: credential.deviceId,
    deviceMlKemPublicKey: normalizedMlKem,
    issuedAt: issuedAt,
    transportPeerId: credential.transportPeerId,
    transportPublicKey: credential.transportPublicKey,
  );
  final signedPayload = directLinkedDeviceQrSignedPayload(canonicalBody);

  final accountSignature = await _sign(
    callSign,
    signedPayload,
    accountPrivateKey.trim(),
  );
  if (accountSignature == null) {
    return (BuildDirectLinkedDeviceQrResult.signingError, null);
  }
  final transportSignature = await _sign(
    callSign,
    signedPayload,
    credential.transportPrivateKey,
  );
  if (transportSignature == null) {
    return (BuildDirectLinkedDeviceQrResult.signingError, null);
  }

  final document = jsonEncode(<String, Object?>{
    _envelopeKey: SplayTreeMap<String, Object?>.from(<String, Object?>{
      'accountSignature': accountSignature,
      'body': jsonDecode(canonicalBody),
      'purpose': directLinkedDeviceQrPurpose,
      'transportSignature': transportSignature,
      'version': directLinkedDeviceQrVersion,
    }),
  });
  if (utf8.encode(document).length > directLinkedDeviceQrMaxBytes) {
    return (BuildDirectLinkedDeviceQrResult.invalidMaterial, null);
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'DIRECT_LINKED_DEVICE_QR_BUILT',
    details: {'deviceId': credential.deviceId},
  );
  return (BuildDirectLinkedDeviceQrResult.success, document);
}

Future<String?> _sign(
  Future<Map<String, dynamic>> Function(String, String) callSign,
  String data,
  String privateKey,
) async {
  try {
    final response = await callSign(data, privateKey);
    if (response['ok'] != true) {
      return null;
    }
    final signature = response['signature'];
    if (signature is! String || signature.trim().isEmpty) {
      return null;
    }
    return signature.trim();
  } catch (error) {
    emitFlowEvent(
      layer: 'FL',
      event: 'DIRECT_LINKED_DEVICE_QR_SIGN_ERROR',
      details: {'errorType': error.runtimeType.toString()},
    );
    return null;
  }
}

/// Parses, authenticates, and authorizes one scanned linked-device document.
///
/// On success the caller may stage EXACTLY ONE pending binding. This function
/// performs no contact, ML-KEM, wake-token, contact-request, intro, network,
/// or notification mutation of any kind — a scan that fails any check below
/// leaves the device in precisely the state it started in.
///
/// [lookupContact] resolves the LOCAL contact for the document's account peer.
/// A device is only ever admitted for a contact the user already knows: the
/// dual signature proves who the device belongs to, not that the user wants to
/// talk to them.
Future<(ParseDirectLinkedDeviceQrResult, DirectLinkedDeviceQrDocument?)>
parseDirectLinkedDeviceQr({
  required String qrString,
  required String ownAccountPeerId,
  required Future<ContactModel?> Function(String accountPeerId) lookupContact,
  required Future<bool> Function({
    required String publicKey,
    required String data,
    required String signature,
  })
  callVerify,
  DirectLinkedDeviceSelector selector = const DirectLinkedDeviceSelector(),
  DateTime Function()? now,
}) async {
  if (!selector.allowsLinkedDeviceAuthoring) {
    return (ParseDirectLinkedDeviceQrResult.selectorDisabled, null);
  }

  if (qrString.trim().isEmpty ||
      utf8.encode(qrString).length > directLinkedDeviceQrMaxBytes) {
    return _malformed('size');
  }

  final Object? decoded;
  try {
    decoded = jsonDecode(qrString);
  } catch (_) {
    return _malformed('json');
  }
  if (decoded is! Map<String, dynamic>) {
    return _malformed('root_shape');
  }
  // Exactly one top-level key. A legacy contact QR has none of this and is
  // rejected here without ever reaching signature verification.
  if (decoded.length != 1 || !decoded.containsKey(_envelopeKey)) {
    return _malformed('envelope');
  }
  final envelope = decoded[_envelopeKey];
  if (envelope is! Map<String, dynamic>) {
    return _malformed('envelope_shape');
  }
  if (envelope.keys.toSet().length != _requiredEnvelopeKeys.length ||
      !envelope.keys.toSet().containsAll(_requiredEnvelopeKeys)) {
    return _malformed('envelope_keys');
  }
  if (envelope['purpose'] != directLinkedDeviceQrPurpose) {
    return _malformed('purpose');
  }
  if (envelope['version'] != directLinkedDeviceQrVersion) {
    return _malformed('version');
  }
  final body = envelope['body'];
  if (body is! Map<String, dynamic>) {
    return _malformed('body_shape');
  }
  // An exact key set — no extra fields. Anything else could be unsigned data
  // a caller later reads as if it had been authenticated.
  if (body.keys.toSet().length != _requiredBodyKeys.length ||
      !body.keys.toSet().containsAll(_requiredBodyKeys)) {
    return _malformed('body_keys');
  }

  final accountPeerId = _boundedString(body['accountPeerId'], _maxPeerIdLength);
  final accountPublicKey = _boundedString(
    body['accountPublicKey'],
    _maxPublicKeyLength,
  );
  final deviceId = _boundedString(body['deviceId'], _maxDeviceIdLength);
  final deviceMlKemPublicKey = _boundedString(
    body['deviceMlKemPublicKey'],
    _maxMlKemPublicKeyLength,
  );
  final issuedAt = _boundedString(body['issuedAt'], _maxIssuedAtLength);
  final transportPeerId = _boundedString(
    body['transportPeerId'],
    _maxPeerIdLength,
  );
  final transportPublicKey = _boundedString(
    body['transportPublicKey'],
    _maxPublicKeyLength,
  );
  final accountSignature = _boundedString(
    envelope['accountSignature'],
    _maxSignatureLength,
  );
  final transportSignature = _boundedString(
    envelope['transportSignature'],
    _maxSignatureLength,
  );
  if (accountPeerId == null ||
      accountPublicKey == null ||
      deviceId == null ||
      deviceMlKemPublicKey == null ||
      issuedAt == null ||
      transportPeerId == null ||
      transportPublicKey == null ||
      accountSignature == null ||
      transportSignature == null) {
    return _malformed('field_bounds');
  }

  if (accountPeerId == ownAccountPeerId.trim()) {
    return (ParseDirectLinkedDeviceQrResult.selfScan, null);
  }

  // The two identities must be genuinely distinct. Equal halves would mean a
  // single key "independently" signing twice, which proves nothing.
  if (transportPeerId == accountPeerId ||
      transportPublicKey == accountPublicKey ||
      accountSignature == transportSignature) {
    return (ParseDirectLinkedDeviceQrResult.invalidSignature, null);
  }

  // Canonical UTC only. The legacy contact parser falls back to "continue
  // without expiration check" when a timestamp will not parse; inheriting that
  // here would make an unparseable issued-at a way to bypass expiry entirely.
  final DateTime issuedAtUtc;
  try {
    if (!issuedAt.endsWith('Z')) {
      return (ParseDirectLinkedDeviceQrResult.invalidTimestamp, null);
    }
    final parsed = DateTime.parse(issuedAt);
    if (!parsed.isUtc) {
      return (ParseDirectLinkedDeviceQrResult.invalidTimestamp, null);
    }
    issuedAtUtc = parsed;
  } catch (_) {
    return (ParseDirectLinkedDeviceQrResult.invalidTimestamp, null);
  }
  final currentTime = (now ?? DateTime.now)().toUtc();
  if (issuedAtUtc.isAfter(currentTime.add(directLinkedDeviceQrMaxFutureSkew))) {
    return (ParseDirectLinkedDeviceQrResult.futureSkew, null);
  }
  if (currentTime.difference(issuedAtUtc) > directLinkedDeviceQrMaxAge) {
    return (ParseDirectLinkedDeviceQrResult.expired, null);
  }

  // Offline: each claimed peer must be the peer its carried key derives to.
  if (!ed25519PublicKeyMatchesPeerId(
        base64PublicKey: accountPublicKey,
        claimedPeerId: accountPeerId,
      ) ||
      !ed25519PublicKeyMatchesPeerId(
        base64PublicKey: transportPublicKey,
        claimedPeerId: transportPeerId,
      )) {
    return (ParseDirectLinkedDeviceQrResult.peerDerivationMismatch, null);
  }

  final contact = await lookupContact(accountPeerId);
  if (contact == null) {
    return (ParseDirectLinkedDeviceQrResult.unknownContact, null);
  }
  if (contact.isBlocked) {
    return (ParseDirectLinkedDeviceQrResult.blockedContact, null);
  }
  if (contact.peerId.trim() != accountPeerId ||
      contact.publicKey.trim() != accountPublicKey) {
    return (ParseDirectLinkedDeviceQrResult.contactKeyMismatch, null);
  }

  // Verification runs LAST, over the canonical body this parser rebuilt from
  // the exact validated field set — not over the raw scanned bytes.
  final signedPayload = directLinkedDeviceQrSignedPayload(
    canonicalDirectLinkedDeviceQrBody(
      accountPeerId: accountPeerId,
      accountPublicKey: accountPublicKey,
      deviceId: deviceId,
      deviceMlKemPublicKey: deviceMlKemPublicKey,
      issuedAt: issuedAt,
      transportPeerId: transportPeerId,
      transportPublicKey: transportPublicKey,
    ),
  );

  final accountSignatureValid = await _verify(
    callVerify,
    publicKey: accountPublicKey,
    data: signedPayload,
    signature: accountSignature,
  );
  if (!accountSignatureValid) {
    return (ParseDirectLinkedDeviceQrResult.invalidSignature, null);
  }
  final transportSignatureValid = await _verify(
    callVerify,
    publicKey: transportPublicKey,
    data: signedPayload,
    signature: transportSignature,
  );
  if (!transportSignatureValid) {
    return (ParseDirectLinkedDeviceQrResult.invalidSignature, null);
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'DIRECT_LINKED_DEVICE_QR_AUTHENTICATED',
    details: {'deviceId': deviceId},
  );
  return (
    ParseDirectLinkedDeviceQrResult.success,
    DirectLinkedDeviceQrDocument(
      accountPeerId: accountPeerId,
      accountPublicKey: accountPublicKey,
      deviceId: deviceId,
      deviceMlKemPublicKey: deviceMlKemPublicKey,
      issuedAt: issuedAt,
      transportPeerId: transportPeerId,
      transportPublicKey: transportPublicKey,
    ),
  );
}

/// Fully verifies the exact Plan-360 QR bytes for a selected group owned by
/// the same logical account.
///
/// No contact lookup or linked-credential lookup is performed. An ordinary
/// primary is allowed to qualify the remote installation solely from the
/// carried account+transport signatures; the receiver later requalifies the
/// same tuple against its active local linked credential and ML-KEM key.
Future<(ParseLinkedGroupBootstrapQrResult, DirectLinkedDeviceQrDocument?)>
parseLinkedGroupBootstrapQr({
  required String qrString,
  required String ownAccountPeerId,
  required String ownAccountPublicKey,
  required bool isOrdinaryPrimary,
  required Future<bool> Function({
    required String publicKey,
    required String data,
    required String signature,
  })
  callVerify,
  DirectLinkedDeviceSelector selector = const DirectLinkedDeviceSelector(),
  bool multiDeviceSyncEnabled = kMultiDeviceSyncEnabled,
  DateTime Function()? now,
}) async {
  if (!selector.allowsLinkedDeviceAuthoring) {
    return (ParseLinkedGroupBootstrapQrResult.selectorDisabled, null);
  }
  if (!multiDeviceSyncEnabled) {
    return (ParseLinkedGroupBootstrapQrResult.multiDeviceDisabled, null);
  }
  if (!isOrdinaryPrimary) {
    return (ParseLinkedGroupBootstrapQrResult.linkedScannerRefused, null);
  }
  if (qrString.trim().isEmpty ||
      utf8.encode(qrString).length > directLinkedDeviceQrMaxBytes) {
    return (ParseLinkedGroupBootstrapQrResult.malformed, null);
  }

  final Object? decoded;
  try {
    decoded = jsonDecode(qrString);
  } catch (_) {
    return (ParseLinkedGroupBootstrapQrResult.malformed, null);
  }
  if (decoded is! Map<String, dynamic> ||
      decoded.length != 1 ||
      !decoded.containsKey(_envelopeKey)) {
    return (ParseLinkedGroupBootstrapQrResult.malformed, null);
  }
  final envelope = decoded[_envelopeKey];
  if (envelope is! Map<String, dynamic> ||
      envelope.keys.toSet().length != _requiredEnvelopeKeys.length ||
      !envelope.keys.toSet().containsAll(_requiredEnvelopeKeys) ||
      envelope['purpose'] != directLinkedDeviceQrPurpose ||
      envelope['version'] != directLinkedDeviceQrVersion) {
    return (ParseLinkedGroupBootstrapQrResult.malformed, null);
  }
  final body = envelope['body'];
  if (body is! Map<String, dynamic> ||
      body.keys.toSet().length != _requiredBodyKeys.length ||
      !body.keys.toSet().containsAll(_requiredBodyKeys)) {
    return (ParseLinkedGroupBootstrapQrResult.malformed, null);
  }

  final accountPeerId = _boundedString(body['accountPeerId'], _maxPeerIdLength);
  final accountPublicKey = _boundedString(
    body['accountPublicKey'],
    _maxPublicKeyLength,
  );
  final deviceId = _boundedString(body['deviceId'], _maxDeviceIdLength);
  final deviceMlKemPublicKey = _boundedString(
    body['deviceMlKemPublicKey'],
    _maxMlKemPublicKeyLength,
  );
  final issuedAt = _boundedString(body['issuedAt'], _maxIssuedAtLength);
  final transportPeerId = _boundedString(
    body['transportPeerId'],
    _maxPeerIdLength,
  );
  final transportPublicKey = _boundedString(
    body['transportPublicKey'],
    _maxPublicKeyLength,
  );
  final accountSignature = _boundedString(
    envelope['accountSignature'],
    _maxSignatureLength,
  );
  final transportSignature = _boundedString(
    envelope['transportSignature'],
    _maxSignatureLength,
  );
  if (accountPeerId == null ||
      accountPublicKey == null ||
      deviceId == null ||
      deviceMlKemPublicKey == null ||
      issuedAt == null ||
      transportPeerId == null ||
      transportPublicKey == null ||
      accountSignature == null ||
      transportSignature == null) {
    return (ParseLinkedGroupBootstrapQrResult.malformed, null);
  }
  if (accountPeerId != ownAccountPeerId.trim() ||
      accountPublicKey != ownAccountPublicKey.trim()) {
    return (ParseLinkedGroupBootstrapQrResult.accountMismatch, null);
  }
  if (transportPeerId == accountPeerId ||
      transportPublicKey == accountPublicKey ||
      accountSignature == transportSignature ||
      deviceId == accountPeerId) {
    return (ParseLinkedGroupBootstrapQrResult.invalidSignature, null);
  }

  final DateTime issuedAtUtc;
  try {
    if (!issuedAt.endsWith('Z')) {
      return (ParseLinkedGroupBootstrapQrResult.invalidTimestamp, null);
    }
    final parsed = DateTime.parse(issuedAt);
    if (!parsed.isUtc) {
      return (ParseLinkedGroupBootstrapQrResult.invalidTimestamp, null);
    }
    issuedAtUtc = parsed;
  } catch (_) {
    return (ParseLinkedGroupBootstrapQrResult.invalidTimestamp, null);
  }
  final currentTime = (now ?? DateTime.now)().toUtc();
  if (issuedAtUtc.isAfter(currentTime.add(directLinkedDeviceQrMaxFutureSkew))) {
    return (ParseLinkedGroupBootstrapQrResult.futureSkew, null);
  }
  if (currentTime.difference(issuedAtUtc) > directLinkedDeviceQrMaxAge) {
    return (ParseLinkedGroupBootstrapQrResult.expired, null);
  }
  if (!ed25519PublicKeyMatchesPeerId(
        base64PublicKey: accountPublicKey,
        claimedPeerId: accountPeerId,
      ) ||
      !ed25519PublicKeyMatchesPeerId(
        base64PublicKey: transportPublicKey,
        claimedPeerId: transportPeerId,
      )) {
    return (ParseLinkedGroupBootstrapQrResult.peerDerivationMismatch, null);
  }

  final canonicalBody = canonicalDirectLinkedDeviceQrBody(
    accountPeerId: accountPeerId,
    accountPublicKey: accountPublicKey,
    deviceId: deviceId,
    deviceMlKemPublicKey: deviceMlKemPublicKey,
    issuedAt: issuedAt,
    transportPeerId: transportPeerId,
    transportPublicKey: transportPublicKey,
  );
  final signedPayload = directLinkedDeviceQrSignedPayload(canonicalBody);
  final accountValid = await _verify(
    callVerify,
    publicKey: accountPublicKey,
    data: signedPayload,
    signature: accountSignature,
  );
  if (!accountValid) {
    return (ParseLinkedGroupBootstrapQrResult.invalidSignature, null);
  }
  final transportValid = await _verify(
    callVerify,
    publicKey: transportPublicKey,
    data: signedPayload,
    signature: transportSignature,
  );
  if (!transportValid) {
    return (ParseLinkedGroupBootstrapQrResult.invalidSignature, null);
  }

  return (
    ParseLinkedGroupBootstrapQrResult.success,
    DirectLinkedDeviceQrDocument(
      accountPeerId: accountPeerId,
      accountPublicKey: accountPublicKey,
      deviceId: deviceId,
      deviceMlKemPublicKey: deviceMlKemPublicKey,
      issuedAt: issuedAt,
      transportPeerId: transportPeerId,
      transportPublicKey: transportPublicKey,
    ),
  );
}

Future<bool> _verify(
  Future<bool> Function({
    required String publicKey,
    required String data,
    required String signature,
  })
  callVerify, {
  required String publicKey,
  required String data,
  required String signature,
}) async {
  try {
    return await callVerify(
      publicKey: publicKey,
      data: data,
      signature: signature,
    );
  } catch (error) {
    emitFlowEvent(
      layer: 'FL',
      event: 'DIRECT_LINKED_DEVICE_QR_VERIFY_ERROR',
      details: {'errorType': error.runtimeType.toString()},
    );
    return false;
  }
}

(ParseDirectLinkedDeviceQrResult, DirectLinkedDeviceQrDocument?) _malformed(
  String reason,
) {
  emitFlowEvent(
    layer: 'FL',
    event: 'DIRECT_LINKED_DEVICE_QR_MALFORMED',
    details: {'reason': reason},
  );
  return (ParseDirectLinkedDeviceQrResult.malformed, null);
}

String? _boundedString(Object? value, int maxLength) {
  if (value is! String) return null;
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed.length > maxLength) return null;
  // Reject values that carried surrounding whitespace: the canonical body the
  // verifier rebuilds uses the trimmed form, so an untrimmed field would
  // produce a body that never matches what was signed. Failing loudly here is
  // clearer than an "invalid signature" for a whitespace bug.
  if (trimmed != value) return null;
  return trimmed;
}

/// True when [qrString] is a linked-device document rather than a legacy
/// contact QR.
///
/// Used by the shared scanner to route bytes to the right parser without
/// letting either parser see the other's document.
bool isDirectLinkedDeviceQrDocument(String qrString) {
  try {
    final decoded = jsonDecode(qrString);
    if (decoded is! Map<String, dynamic>) return false;
    final envelope = decoded[_envelopeKey];
    return envelope is Map<String, dynamic> &&
        envelope['purpose'] == directLinkedDeviceQrPurpose;
  } catch (_) {
    return false;
  }
}

/// The explicit linked setup/status route's source of authoring inputs.
///
/// Exists so `QRDisplayWired` can render the device document without taking a
/// secure-key-store dependency or knowing how authority is persisted. Its
/// presence is what makes the builder reachable from that route and nowhere
/// else.
class DirectLinkedDeviceQrSource {
  const DirectLinkedDeviceQrSource({
    required this.loadAuthority,
    this.selector = const DirectLinkedDeviceSelector(),
  });

  final Future<LinkedInstallationAuthoritySnapshot> Function() loadAuthority;
  final DirectLinkedDeviceSelector selector;
}
