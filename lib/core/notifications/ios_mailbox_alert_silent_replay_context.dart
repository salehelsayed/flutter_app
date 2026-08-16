import 'dart:async';

final Object _iosMailboxAlertSilentReplayZoneKey = Object();

/// True only for async work descended from one leased iOS inbox page replay.
/// Dart zones keep concurrent live/LAN callbacks outside that generation.
bool get isIosMailboxAlertSilentReplayContext =>
    Zone.current[_iosMailboxAlertSilentReplayZoneKey] == true;

Future<T> runInIosMailboxAlertSilentReplayContext<T>(
  Future<T> Function() action,
) => runZoned(
  action,
  zoneValues: <Object, Object?>{_iosMailboxAlertSilentReplayZoneKey: true},
);
