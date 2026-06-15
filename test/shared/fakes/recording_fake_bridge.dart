import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';

/// Minimal fake [Bridge] that records commands and returns configured
/// responses, lifted verbatim from the single-node `_FakeBridge` in
/// `test/integration/live_direct_notification_integration_test.dart:339-393`
/// (plan 120 Phase G3) so the 2-party simulation and the single-node
/// integration test share one bridge fake.
///
/// Records every `send`ed command (`calledCommands` / `payloadsByCommand`),
/// returns per-command configured responses via [whenCommand], and exposes
/// [onMessageReceived] (the [Bridge] callback the [P2PServiceImpl] under test
/// installs) so a test can inject an incoming direct/relay [ChatMessage], plus
/// [payloadsFor] to assert on what was sent back (e.g. `message:confirm`).
class RecordingFakeBridge extends Bridge {
  final Map<String, FutureOr<String> Function(Map<String, dynamic>?)>
  _handlers = {};
  final List<String> calledCommands = [];
  final Map<String, List<Map<String, dynamic>?>> payloadsByCommand = {};
  bool _initialized = false;

  void whenCommand(
    String cmd,
    FutureOr<String> Function(Map<String, dynamic>?) handler,
  ) {
    _handlers[cmd] = handler;
  }

  List<Map<String, dynamic>?> payloadsFor(String cmd) =>
      List.unmodifiable(payloadsByCommand[cmd] ?? const []);

  @override
  bool get isInitialized => _initialized;

  @override
  Future<void> initialize() async {
    _initialized = true;
  }

  @override
  Future<bool> checkHealth() async => true;

  @override
  Future<void> reinitialize() async {}

  @override
  void dispose() {}

  @override
  Future<String> send(String message) async {
    final request = jsonDecode(message) as Map<String, dynamic>;
    final cmd = request['cmd'] as String;
    final payload = request['payload'] as Map<String, dynamic>?;

    calledCommands.add(cmd);
    payloadsByCommand.putIfAbsent(cmd, () => []).add(payload);

    final handler = _handlers[cmd];
    if (handler != null) {
      return await handler(payload);
    }

    return jsonEncode({
      'ok': false,
      'errorCode': 'UNHANDLED',
      'errorMessage': 'no handler for $cmd',
    });
  }
}
