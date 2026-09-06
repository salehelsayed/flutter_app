import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:synchronized/synchronized.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';

/// FDC-09 §12 / CV-14 (217 §D2) — "distribute my wake-token to these contacts"
/// backfill marker.
///
/// DISTINCT key from [kMlKemReannouncePendingKey] — the two drains must never
/// share storage (a shared key would clobber the ML-KEM re-announce drain).
/// Seeded for existing contacts on the paths that also re-announce ML-KEM keys
/// (online-transition / resume / restore); drained by `retryIncompleteKeyExchanges`
/// in its OWN block, removing a peerId only after its (emission-gated) send
/// succeeds so a partial failure keeps the remainder.
const kWakeTokenPendingKey = 'wake_token_pending';
const kWakeTokenDistributionScheduledKey =
    'wake_token_distribution_scheduled_v1';
final _wakeTokenDistributionMutationLock = Lock();

String _tokenDigest(String token) =>
    sha256.convert(utf8.encode(token)).toString();

Future<Map<String, String>> _readScheduledTokenDigests(
  SecureKeyStore store,
) async {
  final raw = await store.read(kWakeTokenDistributionScheduledKey);
  if (raw == null) return {};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      return {
        for (final entry in decoded.entries)
          if (entry.key is String && entry.value is String)
            entry.key as String: entry.value as String,
      };
    }
  } catch (_) {}
  return {};
}

/// Queues newly issued or previously undistributed tokens, including tokens
/// minted by older builds before authenticated distribution was activated.
/// The persistent digest index prevents successful backfill from being sent
/// again on each startup. The existing pending marker owns retries.
Future<int> reconcileWakeTokenDistribution({
  required SecureKeyStore secureKeyStore,
  required Map<String, String> registeredTokens,
}) => _wakeTokenDistributionMutationLock.synchronized(() async {
  final previous = await _readScheduledTokenDigests(secureKeyStore);
  final current = {
    for (final entry in registeredTokens.entries)
      if (entry.key.isNotEmpty && entry.value.isNotEmpty)
        entry.key: _tokenDigest(entry.value),
  };
  final pending = (await readWakeTokenPendingMarker(
    secureKeyStore,
  )).where(current.containsKey).toSet();
  for (final entry in current.entries) {
    if (previous[entry.key] != entry.value) pending.add(entry.key);
  }
  // Write intent first: a crash before the index write only repeats staging.
  await writeWakeTokenPendingMarker(secureKeyStore, pending.toList()..sort());
  await secureKeyStore.write(
    kWakeTokenDistributionScheduledKey,
    jsonEncode(current),
  );
  return pending.length;
});

/// Retires only the token actually carried by a successful encrypted send.
/// A concurrent token rotation or newly queued contact keeps its own marker.
Future<void> completeWakeTokenDistribution({
  required SecureKeyStore secureKeyStore,
  required String peerId,
  required String token,
}) => _wakeTokenDistributionMutationLock.synchronized(() async {
  if (token.isEmpty) return;
  final scheduled = await _readScheduledTokenDigests(secureKeyStore);
  final digest = scheduled[peerId];
  if (digest != null && digest != _tokenDigest(token)) return;
  final pending = await readWakeTokenPendingMarker(secureKeyStore);
  await writeWakeTokenPendingMarker(
    secureKeyStore,
    pending.where((candidate) => candidate != peerId).toList(),
  );
});

Future<List<String>> readWakeTokenPendingMarker(SecureKeyStore store) async {
  final raw = await store.read(kWakeTokenPendingKey);
  if (raw == null || raw.trim().isEmpty) {
    return const [];
  }
  try {
    final decoded = jsonDecode(raw);
    if (decoded is List) {
      return decoded.whereType<String>().toList();
    }
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'WAKE_TOKEN_PENDING_MARKER_READ_ERROR',
      details: {'error': e.toString()},
    );
  }
  return const [];
}

/// Persists [peerIds]; an empty list clears the secure-storage entry.
Future<void> writeWakeTokenPendingMarker(
  SecureKeyStore store,
  List<String> peerIds,
) async {
  if (peerIds.isEmpty) {
    await store.delete(kWakeTokenPendingKey);
    return;
  }
  await store.write(kWakeTokenPendingKey, jsonEncode(peerIds));
}

/// Records all active, non-blocked contacts as pending wake-token distribution
/// targets (existing-contact backfill).
Future<int> recordWakeTokenPending({
  required SecureKeyStore secureKeyStore,
  required ContactRepository contactRepo,
}) async {
  final contacts = await contactRepo.getActiveContacts();
  final peerIds = contacts
      .where((contact) => !contact.isBlocked)
      .map((contact) => contact.peerId)
      .toList();
  await writeWakeTokenPendingMarker(secureKeyStore, peerIds);
  emitFlowEvent(
    layer: 'FL',
    event: 'WAKE_TOKEN_PENDING_MARKED',
    details: {'count': peerIds.length},
  );
  return peerIds.length;
}
