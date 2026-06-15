import 'dart:convert';

import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';

/// One-shot "re-announce my new ML-KEM key" marker (P0-B).
///
/// Written by the identity restore paths after a successful keygen+save;
/// drained by `retryIncompleteKeyExchanges`, which removes each peerId only
/// after its keyExchangeRetry send succeeds (partial failure keeps the rest).
const kMlKemReannouncePendingKey = 'mlkem_reannounce_pending';

Future<List<String>> readMlKemReannounceMarker(SecureKeyStore store) async {
  final raw = await store.read(kMlKemReannouncePendingKey);
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
      event: 'KEY_REANNOUNCE_MARKER_READ_ERROR',
      details: {'error': e.toString()},
    );
  }
  return const [];
}

/// Persists [peerIds]; an empty list clears the secure-storage entry.
Future<void> writeMlKemReannounceMarker(
  SecureKeyStore store,
  List<String> peerIds,
) async {
  if (peerIds.isEmpty) {
    await store.delete(kMlKemReannouncePendingKey);
    return;
  }
  await store.write(kMlKemReannouncePendingKey, jsonEncode(peerIds));
}

/// Records all active contacts as pending re-announcement targets.
Future<int> recordMlKemReannouncePending({
  required SecureKeyStore secureKeyStore,
  required ContactRepository contactRepo,
}) async {
  final contacts = await contactRepo.getActiveContacts();
  final peerIds = contacts
      .where((contact) => !contact.isBlocked)
      .map((contact) => contact.peerId)
      .toList();
  await writeMlKemReannounceMarker(secureKeyStore, peerIds);
  emitFlowEvent(
    layer: 'FL',
    event: 'KEY_REANNOUNCE_MARKED',
    details: {'count': peerIds.length},
  );
  return peerIds.length;
}
