import 'dart:async';

/// Live read of the Android recovery marker's `genericMayHaveAlerted`
/// disposition through the Plan-374 native bridge. `true` means a coalesced
/// deleted-batch generic card may already have made the one sound.
typedef ReadAndroidRecoveryGenericAlertDisposition = Future<bool> Function();

final Object _androidRecoveryAlertDispositionZoneKey = Object();

/// The Plan-372 final-effect tone consultation for Android recovery work.
///
/// Outside the one installed headless recovery graph this returns `false`
/// (normal exact per-event tone arbitration). Inside it, the disposition is
/// re-read at each event: a fixed-only `false` marker never suppresses the
/// canonical tone, while a preserved deletion `true` retains the conservative
/// silent behavior. A failed or ambiguous read is conservatively `true` —
/// never guess an event identity or a recent-sound horizon instead.
Future<bool> readAmbientAndroidRecoveryGenericAlertAmbiguity() async {
  final reader = Zone.current[_androidRecoveryAlertDispositionZoneKey];
  if (reader is! ReadAndroidRecoveryGenericAlertDisposition) return false;
  try {
    return await reader();
  } on Object {
    return true;
  }
}

/// Installs [reader] for every async descendant of [action]. Dart zones keep
/// concurrent foreground callbacks outside the recovery generation.
Future<T> runWithAndroidRecoveryGenericAlertDisposition<T>({
  required ReadAndroidRecoveryGenericAlertDisposition reader,
  required Future<T> Function() action,
}) => runZoned(
  action,
  zoneValues: <Object, Object?>{
    _androidRecoveryAlertDispositionZoneKey: reader,
  },
);
