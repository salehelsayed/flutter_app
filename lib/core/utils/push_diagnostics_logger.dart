import 'dart:developer' as developer;

import 'dart:convert';
import 'package:crypto/crypto.dart';

import 'flow_event_emitter.dart';

String summarizePushToken(String? token) {
  if (token == null || token.isEmpty) {
    return '<none>';
  }
  final digest = sha256.convert(utf8.encode(token)).toString();
  return 'sha256:$digest(length=${token.length})';
}

void logPushDiagnostic(
  String event, {
  Map<String, Object?> details = const {},
}) {
  final sanitizedDetails = sanitizeFlowEventDetails(
    Map<String, dynamic>.from(details),
  );
  final suffix = sanitizedDetails.entries
      .map((entry) => '${entry.key}=${entry.value}')
      .join(' ');
  final line = suffix.isEmpty
      ? '[PUSH_DIAG] $event'
      : '[PUSH_DIAG] $event $suffix';
  // `devicectl device process launch --console` reliably captures stdout/stderr
  // from release/TestFlight apps, while `developer.log` is not always surfaced
  // in that path. Emit to both so device-side debugging works from the terminal.
  // ignore: avoid_print
  print(line);
  developer.log(line, name: 'mknoon.push');
}
