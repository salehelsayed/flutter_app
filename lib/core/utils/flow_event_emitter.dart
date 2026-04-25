import 'dart:convert';
import 'package:flutter/foundation.dart';

/// Whether flow event logging is enabled.
/// Defaults to kDebugMode — disabled in profile/release builds.
bool flowEventLoggingEnabled = kDebugMode;

typedef FlowEventSink = void Function(Map<String, dynamic> payload);

FlowEventSink? _flowEventTestSink;

@visibleForTesting
void debugSetFlowEventSink(FlowEventSink? sink) {
  _flowEventTestSink = sink;
}

void emitFlowEvent({
  required String layer,
  required String event,
  required Map<String, dynamic> details,
}) {
  final payload = {
    'ts': DateTime.now().toUtc().toIso8601String(),
    'milestone': 'M1_IDENTITY_INIT',
    'layer': layer,
    'event': event,
    'details': details,
  };
  _flowEventTestSink?.call(payload);

  if (!flowEventLoggingEnabled) return;
  debugPrint('[FLOW] ${jsonEncode(payload)}');
}
