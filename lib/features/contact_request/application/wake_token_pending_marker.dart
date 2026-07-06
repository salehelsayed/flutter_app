import 'dart:convert';

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
