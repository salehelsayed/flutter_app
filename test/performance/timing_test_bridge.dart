import 'dart:convert';

import '../core/bridge/fake_bridge.dart';

/// A [PassthroughCryptoBridge] subclass with configurable per-command delays
/// and timing field injection for simulating Go-side latency in Dart-only tests.
///
/// Extends [PassthroughCryptoBridge] so message.encrypt/decrypt work
/// transparently without explicit response configuration.
class TimingTestBridge extends PassthroughCryptoBridge {
  /// Per-command artificial delays (simulates Go processing time).
  final Map<String, Duration> commandDelays;

  /// Per-command extra fields merged into response (simulates Go timing fields).
  final Map<String, Map<String, dynamic>> responseTimingFields;

  TimingTestBridge({
    this.commandDelays = const {},
    this.responseTimingFields = const {},
  });

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;

    final delay = cmd != null ? commandDelays[cmd] : null;
    if (delay != null) {
      await Future<void>.delayed(delay);
    }

    final baseResponse = await super.send(message);

    if (cmd != null && responseTimingFields.containsKey(cmd)) {
      final responseMap = jsonDecode(baseResponse) as Map<String, dynamic>;
      responseMap.addAll(responseTimingFields[cmd]!);
      return jsonEncode(responseMap);
    }

    return baseResponse;
  }
}
