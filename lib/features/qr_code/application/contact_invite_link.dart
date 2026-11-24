import 'dart:collection';
import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/qr_code/application/parse_qr_payload_use_case.dart';

const _invitePrefix = 'https://invite.mknoon.xyz/i/v1#';
const _inviteLifetime = Duration(hours: 24);
const _maxFragmentLength = 2048;
const _maxQrBytes = _maxFragmentLength * 3 ~/ 4;
const _contactQrFields = {'ns', 'pk', 'rv', 'sig', 'ts', 'un'};
final _invalidFragmentCharacter = RegExp(r'[^A-Za-z0-9_-]');

typedef VerifiedContactInvite = ({ContactModel contact, DateTime expiresAt});

/// Wraps the existing signed QR JSON in the versioned HTTPS invite.
String? buildContactInviteLink(String signedQr) {
  if (signedQr.length > _maxQrBytes) return null;
  final bytes = utf8.encode(signedQr);
  if (bytes.length > _maxQrBytes ||
      _canonicalContactQrTimestamp(signedQr) == null) {
    return null;
  }
  return '$_invitePrefix${_encodeFragment(bytes)}';
}

/// Unwraps an invite and delegates identity and signature checks to the QR parser.
Future<(ParseQRResult, ContactModel?)> parseContactInviteLink({
  required String link,
  required Bridge bridge,
  required String ownPeerId,
}) async {
  final (result, invite) = await verifyContactInviteLink(
    link: link,
    bridge: bridge,
    ownPeerId: ownPeerId,
  );
  return (result, invite?.contact);
}

/// Verifies the invite and carries forward the expiry from its signed timestamp.
Future<(ParseQRResult, VerifiedContactInvite?)> verifyContactInviteLink({
  required String link,
  required Bridge bridge,
  required String ownPeerId,
}) async {
  final decoded = _decodeInvite(link);
  if (decoded == null) return (ParseQRResult.invalidJson, null);
  final (result, contact) = await parseQRPayload(
    qrString: decoded.signedQr,
    bridge: bridge,
    ownPeerId: ownPeerId,
    maxAge: _inviteLifetime,
  );
  if (contact == null) return (result, null);
  final issuedAt = DateTime.parse(decoded.timestamp).toUtc();
  return (result, (contact: contact, expiresAt: issuedAt.add(_inviteLifetime)));
}

({String signedQr, String timestamp})? _decodeInvite(String link) {
  if (link.length > _invitePrefix.length + _maxFragmentLength ||
      !link.startsWith(_invitePrefix)) {
    return null;
  }
  final fragment = link.substring(_invitePrefix.length);
  if (fragment.isEmpty || _invalidFragmentCharacter.hasMatch(fragment)) {
    return null;
  }
  try {
    final bytes = base64Url.decode(base64Url.normalize(fragment));
    final signedQr = utf8.decode(bytes);
    if (_encodeFragment(utf8.encode(signedQr)) != fragment) return null;
    final timestamp = _canonicalContactQrTimestamp(signedQr);
    return timestamp == null
        ? null
        : (signedQr: signedQr, timestamp: timestamp);
  } on FormatException {
    return null;
  }
}

String _encodeFragment(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

String? _canonicalContactQrTimestamp(String signedQr) {
  try {
    final decoded = jsonDecode(signedQr);
    if (decoded is! Map<String, dynamic> ||
        decoded.length != _contactQrFields.length ||
        !_contactQrFields.every((key) => decoded[key] is String)) {
      return null;
    }
    // Duplicate fields and alternate JSON spellings cannot survive re-encoding.
    if (jsonEncode(SplayTreeMap<String, dynamic>.from(decoded)) != signedQr) {
      return null;
    }
    return decoded['ts'] as String;
  } on FormatException {
    return null;
  }
}
