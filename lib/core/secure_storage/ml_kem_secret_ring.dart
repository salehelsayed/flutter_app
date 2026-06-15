import 'dart:convert';

import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

/// Secure-storage ring of PRIOR ML-KEM secret keys (newest first).
///
/// When an identity restore/recovery regenerates the ML-KEM key pair, the
/// previous secret is pushed here so 1:1 traffic encrypted to the old public
/// key stays decryptable on the same device (P0-B). Kept at the
/// SecureKeyStore level on purpose: the `IdentityRepository` interface has
/// dozens of `implements`-based fakes that would all break on a new member.
const kMlKemSecretKeyRingKey = 'identity_ml_kem_secret_key_ring';
const kMlKemSecretKeyRingCap = 3;

Future<List<String>> loadMlKemSecretKeyRing(SecureKeyStore store) async {
  final raw = await store.read(kMlKemSecretKeyRingKey);
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
      event: 'MLKEM_RING_READ_ERROR',
      details: {'error': e.toString()},
    );
  }
  return const [];
}

/// Pushes [previousSecret] onto the ring (newest first, deduplicated,
/// capped at [kMlKemSecretKeyRingCap]).
Future<void> pushMlKemSecretKeyRing(
  SecureKeyStore store,
  String previousSecret,
) async {
  final ring = await loadMlKemSecretKeyRing(store);
  final updated = <String>[
    previousSecret,
    ...ring.where((entry) => entry != previousSecret),
  ].take(kMlKemSecretKeyRingCap).toList();
  await store.write(kMlKemSecretKeyRingKey, jsonEncode(updated));
  emitFlowEvent(
    layer: 'FL',
    event: 'MLKEM_RING_PUSHED',
    details: {'ringSize': updated.length},
  );
}
