import 'dart:convert';
import 'package:flutter/foundation.dart';

/// Whether flow event logging is enabled.
/// Defaults to kDebugMode — disabled in profile/release builds.
bool flowEventLoggingEnabled = kDebugMode;

void emitFlowEvent({
  required String layer,
  required String event,
  required Map<String, dynamic> details,
}) {
  if (!flowEventLoggingEnabled) return;
  final payload = {
    'ts': DateTime.now().toUtc().toIso8601String(),
    'milestone': 'M1_IDENTITY_INIT',
    'layer': layer,
    'event': event,
    'details': details,
  };
  debugPrint('[FLOW] ${jsonEncode(payload)}');
}
