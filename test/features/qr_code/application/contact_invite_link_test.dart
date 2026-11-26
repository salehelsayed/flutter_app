import 'dart:collection';
import 'dart:convert';

import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/qr_code/application/contact_invite_link.dart';
import 'package:flutter_app/features/qr_code/application/parse_qr_payload_use_case.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../shared/fakes/ed25519_contact_request_crypto.dart';

const _invitePrefix = 'https://invite.mknoon.xyz/i/v1#';
const _username = 'رُبى';
const _relay = '/dns/mknoun.xyz/tcp/4001/wss/p2p/relay';
const _deadline = Duration(seconds: 3);

String _signedQr(
  TestEd25519Identity sender, {
  DateTime? issuedAt,
  String? claimedPeerId,
  String username = _username,
}) {
  final unsigned = SplayTreeMap<String, String>.from({
    'ns': claimedPeerId ?? sender.peerId,
    'pk': sender.publicKey,
    'rv': _relay,
    'ts': (issuedAt ?? DateTime.now()).toUtc().toIso8601String(),
    'un': username,
  });
  final signature = sender.signBase64(jsonEncode(unsigned));
  return jsonEncode(
    SplayTreeMap<String, String>.from({...unsigned, 'sig': signature}),
  );
}

String _fragmentFor(String signedQr) =>
    base64Url.encode(utf8.encode(signedQr)).replaceAll('=', '');

String _inviteFor(String signedQr) => '$_invitePrefix${_fragmentFor(signedQr)}';

void main() {
  final sender = TestEd25519Identity.fromSeedByte(0x42);
  final receiver = TestEd25519Identity.fromSeedByte(0x41);
  late Ed25519ContactRequestBridge bridge;

  setUp(() {
    bridge = Ed25519ContactRequestBridge(Ed25519ContactRequestCryptoBus());
  });

  Future<(ParseQRResult, ContactModel?)> parse(String link) {
    return parseContactInviteLink(
      link: link,
      bridge: bridge,
      ownPeerId: receiver.peerId,
    ).timeout(_deadline);
  }

  test('builds the canonical HTTPS invite with the exact signed QR bytes', () {
    final signedQr = _signedQr(sender);
    expect(buildContactInviteLink(signedQr), _inviteFor(signedQr));
  });

  test(
    'parses an independently constructed invite and verifies the sender',
    () async {
      final issuedAt = DateTime.now().subtract(
        const Duration(hours: 23, minutes: 59),
      );
      final signedQr = _signedQr(sender, issuedAt: issuedAt);

      final (result, contact) = await parse(_inviteFor(signedQr));

      expect(result, ParseQRResult.success);
      expect(contact?.peerId, sender.peerId);
      expect(contact?.publicKey, sender.publicKey);
      expect(contact?.username, _username);
      expect(contact?.rendezvous, _relay);
      expect(bridge.verifyCalls, 1);
    },
  );

  test('rejects a changed name under the original signature', () async {
    final payload = jsonDecode(_signedQr(sender)) as Map<String, dynamic>;
    payload['un'] = 'Changed name';

    expect(await parse(_inviteFor(jsonEncode(payload))), (
      ParseQRResult.invalidSignature,
      null,
    ));
    expect(bridge.verifyCalls, 1);
  });

  test('rejects a key whose peer ID belongs to someone else', () async {
    final signedQr = _signedQr(sender, claimedPeerId: receiver.peerId);

    expect(await parse(_inviteFor(signedQr)), (
      ParseQRResult.invalidSignature,
      null,
    ));
    expect(bridge.commands, isEmpty);
  });

  test('rejects a signed self-invite before verification', () async {
    expect(await parse(_inviteFor(_signedQr(receiver))), (
      ParseQRResult.selfScan,
      null,
    ));
    expect(bridge.commands, isEmpty);
  });

  test('applies the signed QR timestamp window to invite links', () async {
    final now = DateTime.now();
    final expiredQr = _signedQr(
      sender,
      issuedAt: now.subtract(const Duration(hours: 24, minutes: 1)),
    );
    final futureQr = _signedQr(
      sender,
      issuedAt: now.add(const Duration(minutes: 1)),
    );

    expect(await parse(_inviteFor(expiredQr)), (ParseQRResult.expired, null));
    expect(await parse(_inviteFor(futureQr)), (
      ParseQRResult.invalidJson,
      null,
    ));
    expect(bridge.commands, isEmpty);
  });

  test('rejects alternate URL forms before any bridge call', () async {
    final fragment = _fragmentFor(_signedQr(sender));
    final invalidLinks = {
      'HTTP scheme': 'http://invite.mknoon.xyz/i/v1#$fragment',
      'custom scheme': 'mknoon://invite/i/v1#$fragment',
      'other host': 'https://invite.mknoon.xyz.example.org/i/v1#$fragment',
      'userinfo': 'https://user@invite.mknoon.xyz/i/v1#$fragment',
      'explicit port': 'https://invite.mknoon.xyz:443/i/v1#$fragment',
      'other version': 'https://invite.mknoon.xyz/i/v2#$fragment',
      'extra path': 'https://invite.mknoon.xyz/i/v1/extra#$fragment',
      'query': 'https://invite.mknoon.xyz/i/v1?extra=1#$fragment',
      'missing fragment': 'https://invite.mknoon.xyz/i/v1',
      'empty fragment': _invitePrefix,
      'second fragment marker': '$_invitePrefix$fragment#extra',
      'padding': '$_invitePrefix$fragment=',
      'percent escape': '$_invitePrefix%41$fragment',
      'invalid alphabet': '$_invitePrefix$fragment+',
      'invalid base64 length': '${_invitePrefix}A',
      'invalid UTF-8': '${_invitePrefix}_w',
    };
    for (final entry in invalidLinks.entries) {
      expect(await parse(entry.value), (
        ParseQRResult.invalidJson,
        null,
      ), reason: entry.key);
    }
    expect(bridge.commands, isEmpty);
  });

  test(
    'rejects duplicate and unsupported QR fields before verification',
    () async {
      final signedQr = _signedQr(sender);
      final malformed = {
        'duplicate peer ID':
            '{"ns":"${sender.peerId}",${signedQr.substring(1)}',
        'unknown field': '{"kind":"device_link",${signedQr.substring(1)}',
        'legacy ML-KEM field': '{"mlkem":"legacy",${signedQr.substring(1)}',
      };
      for (final entry in malformed.entries) {
        expect(buildContactInviteLink(entry.value), isNull, reason: entry.key);
        expect(await parse(_inviteFor(entry.value)), (
          ParseQRResult.invalidJson,
          null,
        ), reason: entry.key);
      }
      expect(bridge.commands, isEmpty);
    },
  );

  test('rejects a UTF-8 byte-order mark before signed QR JSON', () async {
    final signedQr = '\uFEFF${_signedQr(sender)}';

    expect(await parse(_inviteFor(signedQr)), (
      ParseQRResult.invalidJson,
      null,
    ));
    expect(bridge.commands, isEmpty);
  });

  test('rejects an oversized signed payload before verification', () async {
    final signedQr = _signedQr(sender, username: 'x' * 8192);

    expect(buildContactInviteLink(signedQr), isNull);
    expect(await parse(_inviteFor(signedQr)), (
      ParseQRResult.invalidJson,
      null,
    ));
    expect(bridge.commands, isEmpty);
  });
}
