import 'package:flutter_app/features/account_migration/application/migration_pairing_session_repository_impl.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_qr_payload.dart';
import 'package:flutter_app/features/account_migration/domain/repositories/migration_pairing_session_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/secure_storage/fake_secure_key_store.dart';

void main() {
  group('SecureKeyStoreMigrationPairingSessionRepository', () {
    late FakeSecureKeyStore secureKeyStore;
    final now = DateTime.utc(2026, 1, 1, 12);

    MigrationQrPayload payload({String sessionId = 'mig-session-1'}) {
      return MigrationQrPayload(
        sessionId: sessionId,
        createdAt: now,
        expiresAt: now.add(const Duration(minutes: 5)),
        newPhoneEphemeralPublicKey: 'new-phone-mlkem-public',
      );
    }

    setUp(() {
      secureKeyStore = FakeSecureKeyStore();
    });

    test(
      'consume-before-authorize is durable across repository reload',
      () async {
        final firstRepository = SecureKeyStoreMigrationPairingSessionRepository(
          secureKeyStore: secureKeyStore,
        );

        final firstConsume = await firstRepository.consumeSession(
          payload: payload(),
          consumedAt: now,
        );
        expect(firstConsume, MigrationPairingSessionConsumeResult.consumed);

        final reloadedRepository =
            SecureKeyStoreMigrationPairingSessionRepository(
              secureKeyStore: secureKeyStore,
            );
        expect(
          await reloadedRepository.isSessionConsumed('mig-session-1'),
          true,
        );
        expect(
          (await reloadedRepository.loadConsumedSession(
            'mig-session-1',
          ))!.newPhoneEphemeralPublicKey,
          'new-phone-mlkem-public',
        );
      },
    );

    test('reused session ID is rejected', () async {
      final repository = SecureKeyStoreMigrationPairingSessionRepository(
        secureKeyStore: secureKeyStore,
      );

      expect(
        await repository.consumeSession(payload: payload(), consumedAt: now),
        MigrationPairingSessionConsumeResult.consumed,
      );
      expect(
        await repository.consumeSession(payload: payload(), consumedAt: now),
        MigrationPairingSessionConsumeResult.alreadyConsumed,
      );
    });

    test(
      'stale consumed record remains rejected after restart-style reload',
      () async {
        final originalRepository =
            SecureKeyStoreMigrationPairingSessionRepository(
              secureKeyStore: secureKeyStore,
            );
        await originalRepository.consumeSession(
          payload: payload(),
          consumedAt: now.subtract(const Duration(days: 30)),
        );

        final reloadedRepository =
            SecureKeyStoreMigrationPairingSessionRepository(
              secureKeyStore: secureKeyStore,
            );

        expect(
          await reloadedRepository.consumeSession(
            payload: payload(),
            consumedAt: now,
          ),
          MigrationPairingSessionConsumeResult.alreadyConsumed,
        );
      },
    );
  });
}
