import 'dart:async';

typedef CallNetworkEffectsAllowed = FutureOr<bool> Function();

Future<bool> callNetworkEffectsAreAllowed(
  CallNetworkEffectsAllowed gate,
) async => await gate();

/// Privacy-safe rejection used when account migration or runtime authority has
/// closed every call-network effect.
final class CallNetworkEffectsBlockedException implements Exception {
  const CallNetworkEffectsBlockedException();

  @override
  String toString() => 'CallNetworkEffectsBlockedException';
}

/// Executes [action] only after the current network authority admits it.
///
/// Gate failures are intentionally indistinguishable from a closed gate. This
/// keeps relay lookups and session creation behind the same fail-closed edge.
Future<T> runCallNetworkActionIfAllowed<T>({
  required CallNetworkEffectsAllowed gate,
  required Future<T> Function() action,
}) async {
  var allowed = false;
  try {
    allowed = await callNetworkEffectsAreAllowed(gate);
  } catch (_) {
    allowed = false;
  }
  if (!allowed) throw const CallNetworkEffectsBlockedException();
  return action();
}
