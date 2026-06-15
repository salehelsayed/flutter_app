import 'dart:convert';

import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_qr_payload.dart';
import 'package:flutter_app/features/account_migration/domain/repositories/migration_pairing_session_repository.dart';

class SecureKeyStoreMigrationPairingSessionRepository
    implements MigrationPairingSessionRepository {
  static const storageKey = 'account_migration_pairing_sessions:v1';

  final SecureKeyStore _secureKeyStore;

  const SecureKeyStoreMigrationPairingSessionRepository({
    required SecureKeyStore secureKeyStore,
  }) : _secureKeyStore = secureKeyStore;

  @override
  Future<void> savePendingNewPhoneSession(
    MigrationPendingPairingSession session,
  ) async {
    final store = await _loadStore();
    store.pendingSessions[session.sessionId] = session;
    await _saveStore(store);
  }

  @override
  Future<MigrationPendingPairingSession?> loadPendingNewPhoneSession(
    String sessionId,
  ) async {
    final store = await _loadStore();
    if (store.failClosed) {
      return null;
    }
    return store.pendingSessions[sessionId];
  }

  @override
  Future<MigrationPairingSessionConsumeResult> consumeSession({
    required MigrationQrPayload payload,
    required DateTime consumedAt,
  }) async {
    final store = await _loadStore();
    if (store.failClosed ||
        store.consumedSessions.containsKey(payload.sessionId)) {
      return MigrationPairingSessionConsumeResult.alreadyConsumed;
    }

    store.consumedSessions[payload.sessionId] = MigrationConsumedPairingSession(
      sessionId: payload.sessionId,
      consumedAt: consumedAt.toUtc(),
      qrCreatedAt: payload.createdAt,
      qrExpiresAt: payload.expiresAt,
      newPhoneEphemeralPublicKey: payload.newPhoneEphemeralPublicKey,
    );
    await _saveStore(store);
    return MigrationPairingSessionConsumeResult.consumed;
  }

  @override
  Future<bool> isSessionConsumed(String sessionId) async {
    final store = await _loadStore();
    return store.failClosed || store.consumedSessions.containsKey(sessionId);
  }

  @override
  Future<MigrationConsumedPairingSession?> loadConsumedSession(
    String sessionId,
  ) async {
    final store = await _loadStore();
    if (store.failClosed) {
      return null;
    }
    return store.consumedSessions[sessionId];
  }

  Future<_PairingSessionStore> _loadStore() async {
    final raw = await _secureKeyStore.read(storageKey);
    if (raw == null) {
      return _PairingSessionStore.empty();
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic> || decoded['version'] != 1) {
        return _PairingSessionStore.failClosed();
      }

      final pendingRaw = decoded['pendingSessions'];
      final consumedRaw = decoded['consumedSessions'];
      if (pendingRaw is! Map<String, dynamic> ||
          consumedRaw is! Map<String, dynamic>) {
        return _PairingSessionStore.failClosed();
      }

      return _PairingSessionStore(
        pendingSessions: {
          for (final entry in pendingRaw.entries)
            entry.key: MigrationPendingPairingSession.fromJson(
              Map<String, dynamic>.from(entry.value as Map),
            ),
        },
        consumedSessions: {
          for (final entry in consumedRaw.entries)
            entry.key: MigrationConsumedPairingSession.fromJson(
              Map<String, dynamic>.from(entry.value as Map),
            ),
        },
      );
    } catch (_) {
      return _PairingSessionStore.failClosed();
    }
  }

  Future<void> _saveStore(_PairingSessionStore store) {
    return _secureKeyStore.write(storageKey, jsonEncode(store.toJson()));
  }
}

class _PairingSessionStore {
  final Map<String, MigrationPendingPairingSession> pendingSessions;
  final Map<String, MigrationConsumedPairingSession> consumedSessions;
  final bool failClosed;

  _PairingSessionStore({
    required this.pendingSessions,
    required this.consumedSessions,
    this.failClosed = false,
  });

  factory _PairingSessionStore.empty() {
    return _PairingSessionStore(pendingSessions: {}, consumedSessions: {});
  }

  factory _PairingSessionStore.failClosed() {
    return _PairingSessionStore(
      pendingSessions: {},
      consumedSessions: {},
      failClosed: true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'version': 1,
      'pendingSessions': {
        for (final entry in pendingSessions.entries)
          entry.key: entry.value.toJson(),
      },
      'consumedSessions': {
        for (final entry in consumedSessions.entries)
          entry.key: entry.value.toJson(),
      },
    };
  }
}
