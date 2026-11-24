import 'dart:convert';

import 'package:synchronized/synchronized.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';

/// Pending distribution of our ML-KEM key, after restore or contact consent.
///
/// Written after identity restore or explicit contact acceptance/QR addition;
/// drained by `retryIncompleteKeyExchanges`, which removes each peerId only
/// after its keyExchangeRetry send succeeds (partial failure keeps the rest).
const kMlKemReannouncePendingKey = 'mlkem_reannounce_pending';
final _mlKemReannounceMutationLock = Lock();

Future<List<String>> readMlKemReannounceMarker(SecureKeyStore store) =>
    _mlKemReannounceMutationLock.synchronized(
      () => _readMlKemReannounceMarker(store),
    );

Future<List<String>> _readMlKemReannounceMarker(SecureKeyStore store) async {
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
) => _mlKemReannounceMutationLock.synchronized(
  () => _writeMlKemReannounceMarker(store, peerIds),
);

Future<void> _writeMlKemReannounceMarker(
  SecureKeyStore store,
  List<String> peerIds,
) async {
  if (peerIds.isEmpty) {
    await store.delete(kMlKemReannouncePendingKey);
    return;
  }
  await store.write(kMlKemReannouncePendingKey, jsonEncode(peerIds));
}

/// Establishes durable reconnect/resume ownership before starting a request.
Future<void> queueMlKemReannouncePeer(
  SecureKeyStore store,
  String peerId,
) async {
  await tryQueueMlKemReannouncePeer(store, peerId);
}

/// Establishes or reuses custody if the synchronous guard still allows it.
Future<bool> tryQueueMlKemReannouncePeer(
  SecureKeyStore store,
  String peerId, {
  bool Function()? canQueue,
}) => _mlKemReannounceMutationLock.synchronized(() async {
  if (canQueue?.call() == false) return false;
  final pending = await _readMlKemReannounceMarker(store);
  if (canQueue?.call() == false) return false;
  if (pending.contains(peerId)) return true;

  var current = true;
  try {
    await _writeMlKemReannounceMarker(store, [...pending, peerId]);
  } finally {
    current = canQueue?.call() ?? true;
    if (!current) {
      // Reconnect readers take the same lock. Restore the previous list
      // before any reader can observe the retired action's new marker.
      await _writeMlKemReannounceMarker(store, pending);
    }
  }
  return current;
});

/// Retires one successful retry without overwriting peers queued in flight.
Future<void> completeMlKemReannouncePeer(SecureKeyStore store, String peerId) =>
    _mlKemReannounceMutationLock.synchronized(() async {
      final pending = await _readMlKemReannounceMarker(store);
      await _writeMlKemReannounceMarker(
        store,
        pending.where((candidate) => candidate != peerId).toList(),
      );
    });

/// Records all active contacts as pending re-announcement targets.
Future<int> recordMlKemReannouncePending({
  required SecureKeyStore secureKeyStore,
  required ContactRepository contactRepo,
}) => _mlKemReannounceMutationLock.synchronized(() async {
  final contacts = await contactRepo.getActiveContacts();
  final peerIds = contacts
      .where((contact) => !contact.isBlocked)
      .map((contact) => contact.peerId)
      .toList();
  await _writeMlKemReannounceMarker(secureKeyStore, peerIds);
  emitFlowEvent(
    layer: 'FL',
    event: 'KEY_REANNOUNCE_MARKED',
    details: {'count': peerIds.length},
  );
  return peerIds.length;
});
