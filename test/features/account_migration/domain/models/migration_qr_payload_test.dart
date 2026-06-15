import 'dart:convert';

import 'package:flutter_app/features/account_migration/application/migration_qr_payload_use_case.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_qr_payload.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MigrationQrPayload', () {
    final createdAt = DateTime.utc(2026, 1, 1, 12);
    final expiresAt = createdAt.add(const Duration(minutes: 5));

    MigrationQrPayload payload() {
      return MigrationQrPayload(
        sessionId: 'mig-session-1',
        createdAt: createdAt,
        expiresAt: expiresAt,
        newPhoneEphemeralPublicKey: 'new-phone-mlkem-public',
        channelNonce: 'pairing-channel-nonce',
      );
    }

    test('round-trips with explicit kind and version', () {
      final original = payload();
      final json = original.toJson();

      expect(json['kind'], accountMigrationPairingQrKind);
      expect(json['version'], currentAccountMigrationPairingQrVersion);
      expect(MigrationQrPayload.fromJson(json), original);
    });

    test('contact-style payload without migration kind is rejected', () {
      final contactQrJson = jsonEncode({
        'pk': 'contact-public-key',
        'ns': 'contact-peer-id',
        'rv': '/dns4/relay/tcp/443/p2p/relay',
        'ts': createdAt.toIso8601String(),
        'sig': 'contact-signature',
      });

      final (result, parsed) = parseMigrationQrPayload(
        qrData: contactQrJson,
        now: () => createdAt,
      );

      expect(result, MigrationQrParseResult.wrongKind);
      expect(parsed, isNull);
    });

    test('secret key material is not serialized into QR JSON', () {
      final qrJson = payload().toJsonString();

      expect(qrJson, isNot(contains('secret')));
      expect(qrJson, isNot(contains('new-phone-mlkem-secret')));
      expect(jsonDecode(qrJson), isNot(containsPair('secretKey', anything)));
    });
  });
}
