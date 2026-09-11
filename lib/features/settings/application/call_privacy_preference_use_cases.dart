import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/features/call/domain/call_engine.dart';

// Stable across upgrades. Never seed this key from a build/rollout flag.
const alwaysRelayCallsStorageKey = 'settings_always_relay_calls';

Future<bool> loadAlwaysRelayCallsPreference({
  required SecureKeyStore secureKeyStore,
}) async {
  final value = await secureKeyStore
      .read(alwaysRelayCallsStorageKey)
      .timeout(const Duration(seconds: 2));
  return switch (value) {
    null || 'false' => false,
    'true' => true,
    _ => throw const FormatException('Invalid call privacy preference'),
  };
}

Future<void> saveAlwaysRelayCallsPreference({
  required SecureKeyStore secureKeyStore,
  required bool alwaysRelay,
}) => secureKeyStore.write(alwaysRelayCallsStorageKey, '$alwaysRelay');

/// Resolve once before allocating a call's media bundle. The executor retains
/// this value for the call and every restart. Feature availability deliberately
/// has no bearing on a saved privacy choice, including when the UI is disabled.
Future<CallTransportPolicy> resolveCallTransportPolicy({
  required SecureKeyStore secureKeyStore,
  required bool forceRelay,
}) async {
  if (forceRelay) return CallTransportPolicy.relayOnly;
  try {
    return await loadAlwaysRelayCallsPreference(secureKeyStore: secureKeyStore)
        ? CallTransportPolicy.relayOnly
        : CallTransportPolicy.all;
  } catch (_) {
    // Locked/unavailable storage and unknown future values are not opt-outs.
    return CallTransportPolicy.relayOnly;
  }
}
