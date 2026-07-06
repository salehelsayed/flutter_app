import 'dart:convert';

import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/features/push/domain/received_wake_token_store.dart';

/// SecureKeyStore-backed [ReceivedWakeTokenStore] (FDC-09 §12 / CV-14).
///
/// Persists the {peerId -> {"tok","ts"}} map as a single JSON blob under a
/// DISTINCT key from the recipient-minted [WakeTokenStoreImpl]
/// (`fdc09_wake_tokens`) — the two directions must never share storage.
///
/// Holds an in-memory cache loaded ONCE: the 1:1 `inbox:store` funnel resolves a
/// wake-token on every send, so a SecureKeyStore read per message would be a
/// hot-path cost. The cache is kept coherent on write (updated in place, never
/// invalidated-then-reloaded), so reads after the first load never touch
/// SecureKeyStore. A corrupt/legacy blob clears itself and reads empty (never
/// throws).
const receivedWakeTokensSecureStorageKey = 'fdc09_received_wake_tokens';

class ReceivedWakeTokenStoreImpl implements ReceivedWakeTokenStore {
  final SecureKeyStore _secureKeyStore;

  /// Loaded once from SecureKeyStore, then kept coherent on write.
  Map<String, Map<String, String>>? _cache;

  /// The in-flight cold load, shared by ALL concurrent first-callers. Without
  /// this, two handlers racing the very first load each parse their OWN map and
  /// the second writer clobbers the first's entry (a lost update). Memoizing the
  /// Future makes every caller resolve to the SAME map reference, so concurrent
  /// writes mutate one shared map coherently.
  Future<Map<String, Map<String, String>>>? _loading;

  ReceivedWakeTokenStoreImpl({required SecureKeyStore secureKeyStore})
    : _secureKeyStore = secureKeyStore;

  Future<Map<String, Map<String, String>>> _ensureLoaded() {
    final cached = _cache;
    if (cached != null) return Future.value(cached);
    return _loading ??= _load();
  }

  Future<Map<String, Map<String, String>>> _load() async {
    try {
      final raw = await _secureKeyStore.read(receivedWakeTokensSecureStorageKey);
      if (raw == null || raw.isEmpty) {
        return _cache = <String, Map<String, String>>{};
      }
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final parsed = <String, Map<String, String>>{};
        decoded.forEach((peerId, value) {
          if (value is Map) {
            final tok = value['tok'];
            final ts = value['ts'];
            if (tok is String && ts is String) {
              parsed[peerId] = {'tok': tok, 'ts': ts};
            }
          }
        });
        return _cache = parsed;
      } catch (_) {
        // Corrupt/legacy blob: clear and start fresh (never throws on read).
        await clear();
        return _cache!;
      }
    } finally {
      _loading = null;
    }
  }

  @override
  Future<Map<String, String>?> readTokenFor(String peerId) async {
    final map = await _ensureLoaded();
    final entry = map[peerId];
    return entry == null ? null : Map<String, String>.from(entry);
  }

  @override
  Future<void> writeTokenFor(String peerId, String token, String ts) async {
    final map = await _ensureLoaded();
    map[peerId] = {'tok': token, 'ts': ts};
    await _persist(map);
  }

  @override
  Future<void> removeTokenFor(String peerId) async {
    final map = await _ensureLoaded();
    if (map.remove(peerId) != null) {
      await _persist(map);
    }
  }

  @override
  Future<void> clear() async {
    _cache = <String, Map<String, String>>{};
    _loading = null;
    await _secureKeyStore.delete(receivedWakeTokensSecureStorageKey);
  }

  Future<void> _persist(Map<String, Map<String, String>> map) async {
    if (map.isEmpty) {
      await _secureKeyStore.delete(receivedWakeTokensSecureStorageKey);
      return;
    }
    await _secureKeyStore.write(
      receivedWakeTokensSecureStorageKey,
      jsonEncode(map),
    );
  }
}
