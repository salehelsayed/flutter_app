import 'package:flutter_app/core/secure_storage/secure_key_store.dart';

/// One-shot "this freshly-restored device should announce its new per-device
/// identity to its groups" marker (B1b / R1).
///
/// Written by the identity restore paths on success (mirrors the ML-KEM contact
/// re-announce marker), read+cleared by the startup emit hook. A marker is the
/// only clean restore-vs-normal-restart discriminator: a normal restart re-runs
/// startup identically and never re-mints ML-KEM, so it never sets the marker.
const kGroupDeviceAnnouncePendingKey = 'group_device_announce_pending';

Future<bool> readGroupDeviceAnnounceMarker(SecureKeyStore store) async {
  final raw = await store.read(kGroupDeviceAnnouncePendingKey);
  return raw != null && raw.trim().isNotEmpty;
}

Future<void> markGroupDeviceAnnouncePending(SecureKeyStore store) async {
  await store.write(kGroupDeviceAnnouncePendingKey, '1');
}

Future<void> clearGroupDeviceAnnounceMarker(SecureKeyStore store) async {
  await store.delete(kGroupDeviceAnnouncePendingKey);
}
