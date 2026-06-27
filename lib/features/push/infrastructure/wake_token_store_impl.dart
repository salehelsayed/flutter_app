import 'dart:convert';

import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/features/push/domain/wake_token_store.dart';

/// SecureKeyStore-backed [WakeTokenStore] (FDC-09 §12). Persists the recipient's
/// minted {contactPeerId -> opaque token} map as a single JSON blob, mirroring
/// the [PushTokenStoreImpl] pattern. A corrupt/legacy blob clears itself and
/// reads as empty (never throws).
const wakeTokensSecureStorageKey = 'fdc09_wake_tokens';

class WakeTokenStoreImpl implements WakeTokenStore {
  final SecureKeyStore _secureKeyStore;

  WakeTokenStoreImpl({required SecureKeyStore secureKeyStore})
    : _secureKeyStore = secureKeyStore;

  @override
  Future<Map<String, String>> readTokens() async {
    final raw = await _secureKeyStore.read(wakeTokensSecureStorageKey);
    if (raw == null || raw.isEmpty) {
      return <String, String>{};
    }
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      // Corrupt blob: clear it and start fresh (never throws on read).
      await clear();
      return <String, String>{};
    }
  }

  @override
  Future<void> writeTokens(Map<String, String> tokens) async {
    if (tokens.isEmpty) {
      await clear();
      return;
    }
    await _secureKeyStore.write(wakeTokensSecureStorageKey, jsonEncode(tokens));
  }

  @override
  Future<void> clear() async {
    await _secureKeyStore.delete(wakeTokensSecureStorageKey);
  }
}
