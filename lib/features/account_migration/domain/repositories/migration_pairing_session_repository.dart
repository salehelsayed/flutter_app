import 'package:flutter_app/features/account_migration/domain/models/migration_qr_payload.dart';

enum MigrationPairingSessionConsumeResult { consumed, alreadyConsumed }

abstract class MigrationPairingSessionRepository {
  Future<void> savePendingNewPhoneSession(
    MigrationPendingPairingSession session,
  );

  Future<MigrationPendingPairingSession?> loadPendingNewPhoneSession(
    String sessionId,
  );

  Future<MigrationPairingSessionConsumeResult> consumeSession({
    required MigrationQrPayload payload,
    required DateTime consumedAt,
  });

  Future<bool> isSessionConsumed(String sessionId);

  Future<MigrationConsumedPairingSession?> loadConsumedSession(
    String sessionId,
  );
}
