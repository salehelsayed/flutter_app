import 'dart:convert';

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
  print('[FLOW] ${jsonEncode(payload)}');
}
