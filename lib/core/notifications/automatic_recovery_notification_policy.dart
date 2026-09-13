import 'dart:async';
import 'dart:convert';

import 'package:clock/clock.dart';

/// Recovery never changes message bytes or delivery/custody semantics. This
/// async scope carries only the notification intent to the transport boundary.
const automaticRecoveryAlertAgeLimit = Duration(hours: 24);
final Object _quietRecoveryKey = Object();

bool get isQuietAutomaticRecovery => Zone.current[_quietRecoveryKey] == true;

T runWithAutomaticRecoveryNotificationPolicy<T>({
  required String originalTimestamp,
  required T Function() action,
  bool manualRetry = false,
  DateTime? now,
}) {
  final original = DateTime.tryParse(originalTimestamp)?.toUtc();
  final quiet =
      !manualRetry &&
      original != null &&
      (now ?? clock.now()).toUtc().difference(original) >
          automaticRecoveryAlertAgeLimit;
  return runZoned(action, zoneValues: {_quietRecoveryKey: quiet});
}

/// The cutoff concerns initial direct messages. Edits, reactions, deletion
/// events and controls have separate event clocks and notification contracts.
bool quietRecoveryForEnvelope(String message) {
  if (!isQuietAutomaticRecovery) return false;
  try {
    final value = jsonDecode(message);
    return value is Map<String, dynamic> &&
        value['type'] == 'chat_message' &&
        value['version'] == '2' &&
        !value.containsKey('eventId') &&
        value['encrypted'] is Map;
  } catch (_) {
    return false;
  }
}
