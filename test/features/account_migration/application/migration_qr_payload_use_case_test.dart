import 'dart:convert';

import 'package:flutter_app/features/account_migration/application/migration_pairing_session_repository_impl.dart';
import 'package:flutter_app/features/account_migration/application/migration_qr_payload_use_case.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_qr_payload.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/secure_storage/fake_secure_key_store.dart';

void main() {
  group('migration QR payload use cases', () {
    late FakeBridge bridge;
    late FakeSecureKeyStore secureKeyStore;
    late SecureKeyStoreMigrationPairingSessionRepository repository;
    final now = DateTime.utc(2026, 1, 1, 12);

    setUp(() {
      bridge = FakeBridge();
      bridge.responses['mlkem.keygen'] = {
        'ok': true,
        'publicKey': 'new-phone-mlkem-public',
        'secretKey': 'new-phone-mlkem-secret',
      };
      secureKeyStore = FakeSecureKeyStore();
      repository = SecureKeyStoreMigrationPairingSessionRepository(
        secureKeyStore: secureKeyStore,
      );
    });

    test(
      'build creates session, expiry, and persisted ML-KEM key pair',
      () async {
        final (result, output) = await buildMigrationQrPayload(
          bridge: bridge,
          repository: repository,
          sessionIdProvider: () => 'mig-session-1',
          now: () => now,
          ttl: const Duration(minutes: 5),
        );

        expect(result, BuildMigrationQrPayloadResult.success);
        expect(output, isNotNull);
        expect(output!.payload.sessionId, 'mig-session-1');
        expect(output.payload.createdAt, now);
        expect(output.payload.expiresAt, now.add(const Duration(minutes: 5)));
        expect(
          output.payload.newPhoneEphemeralPublicKey,
          'new-phone-mlkem-public',
        );
        expect(bridge.commandLog, contains('mlkem.keygen'));

        final pending = await repository.loadPendingNewPhoneSession(
          'mig-session-1',
        );
        expect(pending, isNotNull);
        expect(pending!.newPhoneEphemeralPublicKey, 'new-phone-mlkem-public');
        expect(pending.newPhoneEphemeralSecretKey, 'new-phone-mlkem-secret');
        expect(output.qrJson, isNot(contains('new-phone-mlkem-secret')));
      },
    );

    test('parser fails closed for malformed and incompatible payloads', () {
      final base = <String, dynamic>{
        'kind': accountMigrationPairingQrKind,
        'version': currentAccountMigrationPairingQrVersion,
        'sessionId': 'mig-session-1',
        'createdAt': now.toIso8601String(),
        'expiresAt': now.add(const Duration(minutes: 5)).toIso8601String(),
        'newPhoneEphemeralPublicKey': 'new-phone-mlkem-public',
      };

      MigrationQrParseResult resultFor(Map<String, dynamic> payload) {
        final (result, parsed) = parseMigrationQrPayload(
          qrData: jsonEncode(payload),
          now: () => now,
          maxFutureClockSkew: const Duration(minutes: 2),
        );
        expect(parsed, isNull);
        return result;
      }

      expect(
        resultFor({...base, 'createdAt': 'not-a-timestamp'}),
        MigrationQrParseResult.malformedTimestamp,
      );
      expect(
        resultFor({
          ...base,
          'expiresAt': now
              .subtract(const Duration(seconds: 1))
              .toIso8601String(),
        }),
        MigrationQrParseResult.expired,
      );
      expect(
        resultFor({
          ...base,
          'createdAt': now.add(const Duration(minutes: 3)).toIso8601String(),
        }),
        MigrationQrParseResult.futureTimestamp,
      );
      expect(
        resultFor({...base}..remove('newPhoneEphemeralPublicKey')),
        MigrationQrParseResult.missingFields,
      );
      expect(
        resultFor({...base, 'kind': 'contact'}),
        MigrationQrParseResult.wrongKind,
      );
      expect(
        resultFor({...base, 'version': 2}),
        MigrationQrParseResult.unsupportedVersion,
      );
    });

    test('valid timestamp inside skew succeeds', () {
      final (result, parsed) = parseMigrationQrPayload(
        qrData: jsonEncode({
          'kind': accountMigrationPairingQrKind,
          'version': currentAccountMigrationPairingQrVersion,
          'sessionId': 'mig-session-1',
          'createdAt': now.add(const Duration(minutes: 1)).toIso8601String(),
          'expiresAt': now.add(const Duration(minutes: 5)).toIso8601String(),
          'newPhoneEphemeralPublicKey': 'new-phone-mlkem-public',
        }),
        now: () => now,
        maxFutureClockSkew: const Duration(minutes: 2),
      );

      expect(result, MigrationQrParseResult.success);
      expect(parsed, isNotNull);
      expect(parsed!.sessionId, 'mig-session-1');
    });

    test('pairing confirmation code is stable for the QR payload', () {
      final payload = MigrationQrPayload(
        sessionId: 'mig-session-1',
        createdAt: now,
        expiresAt: now.add(const Duration(minutes: 5)),
        newPhoneEphemeralPublicKey: 'new-phone-mlkem-public',
        channelNonce: 'channel-nonce',
      );

      final first = deriveMigrationPairingConfirmationCode(payload);
      final second = deriveMigrationPairingConfirmationCode(
        MigrationQrPayload.fromJson(jsonDecode(payload.toJsonString())),
      );
      final differentSession = deriveMigrationPairingConfirmationCode(
        MigrationQrPayload(
          sessionId: 'mig-session-2',
          createdAt: now,
          expiresAt: now.add(const Duration(minutes: 5)),
          newPhoneEphemeralPublicKey: 'new-phone-mlkem-public',
          channelNonce: 'channel-nonce',
        ),
      );

      expect(first, matches(RegExp(r'^\d{6}$')));
      expect(second, first);
      expect(differentSession, isNot(first));
    });
  });
}
