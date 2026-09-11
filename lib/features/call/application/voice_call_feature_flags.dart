import '../domain/call_engine.dart';

const Map<String, bool> _defaultVoiceCallFeatureFlags = <String, bool>{
  'voice_call_capability_v1': false,
  'voice_call_outgoing_enabled': false,
  'voice_call_incoming_enabled': false,
  'voice_call_turn_enabled': false,
  'voice_call_android_native_enabled': false,
  'voice_call_ios_native_enabled': false,
  'voice_call_always_relay_enabled': false,
  'voice_call_force_relay_enabled': false,
};

/// Returns an independent map so callers cannot mutate the shared defaults.
Map<String, bool> defaultVoiceCallFeatureFlags() =>
    Map<String, bool>.of(_defaultVoiceCallFeatureFlags);

/// Compile-time production gates. Every gate is deliberately false unless an
/// explicit build define enables it; merely linking call code starts nothing.
Map<String, bool> productionVoiceCallFeatureFlags() => <String, bool>{
  'voice_call_capability_v1': const bool.fromEnvironment(
    'VOICE_CALL_CAPABILITY_V1',
  ),
  'voice_call_outgoing_enabled': const bool.fromEnvironment(
    'VOICE_CALL_OUTGOING_ENABLED',
  ),
  'voice_call_incoming_enabled': const bool.fromEnvironment(
    'VOICE_CALL_INCOMING_ENABLED',
  ),
  'voice_call_turn_enabled': const bool.fromEnvironment(
    'VOICE_CALL_TURN_ENABLED',
  ),
  'voice_call_android_native_enabled': const bool.fromEnvironment(
    'VOICE_CALL_ANDROID_NATIVE_ENABLED',
  ),
  'voice_call_ios_native_enabled': const bool.fromEnvironment(
    'VOICE_CALL_IOS_NATIVE_ENABLED',
  ),
  'voice_call_always_relay_enabled': const bool.fromEnvironment(
    'VOICE_CALL_ALWAYS_RELAY_ENABLED',
  ),
  // Independent rollout restriction, never a persisted user preference.
  'voice_call_force_relay_enabled': const bool.fromEnvironment(
    'VOICE_CALL_FORCE_RELAY_ENABLED',
  ),
};

/// Operator-approved discovery endpoints; no implicit third-party STUN service.
/// STUN has no expiring credentials. TURN still comes from the existing provider.
List<CallIceServer> productionVoiceCallStunServers() {
  const configured = String.fromEnvironment('VOICE_CALL_STUN_URLS');
  final urls = configured
      .split(',')
      .map((url) => url.trim())
      .where((url) => url.isNotEmpty)
      .toList(growable: false);
  if (urls.any(
    (url) => !url.startsWith('stun:') && !url.startsWith('stuns:'),
  )) {
    throw const FormatException('Invalid call STUN configuration');
  }
  return List.unmodifiable([
    if (urls.isNotEmpty)
      CallIceServer(urls: urls, expiresAt: DateTime.utc(9999)),
  ]);
}
