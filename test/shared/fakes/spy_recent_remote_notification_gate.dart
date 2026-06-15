import 'dart:io';

import 'package:flutter_app/core/notifications/recent_remote_notification_gate.dart';

/// Records a single ([payload], [messageId]) pair for each gate call.
class RecentNotificationGateCall {
  final String payload;
  final String? messageId;

  const RecentNotificationGateCall({required this.payload, this.messageId});

  @override
  String toString() =>
      'RecentNotificationGateCall(payload: $payload, messageId: $messageId)';
}

/// 120 G4 — spy gate that records every `markAnnouncement` /
/// `consumeIfRecentAnnouncement` call (payload + messageId) so a test can
/// assert the listener call-site wiring directly, while still delegating to a
/// real on-disk [RecentRemoteNotificationGate] backed by a unique temp file
/// (so persistence semantics are exercised and per-instance isolation holds).
///
/// Construct with no args for a unique-temp-file super; pass an explicit
/// [filePath] only when a test needs a stable path.
class SpyRecentRemoteNotificationGate extends RecentRemoteNotificationGate {
  final List<RecentNotificationGateCall> markCalls = [];
  final List<RecentNotificationGateCall> consumeCalls = [];

  SpyRecentRemoteNotificationGate({String? filePath, super.now})
    : super(
        filePath:
            filePath ??
            '${Directory.systemTemp.path}/mknoon_spy_remote_gate_'
                '${DateTime.now().microsecondsSinceEpoch}_${_seq++}.json',
      );

  static int _seq = 0;

  @override
  Future<void> markAnnouncement({
    required String payload,
    String? messageId,
  }) async {
    markCalls.add(
      RecentNotificationGateCall(payload: payload, messageId: messageId),
    );
    await super.markAnnouncement(payload: payload, messageId: messageId);
  }

  @override
  Future<bool> consumeIfRecentAnnouncement({
    required String payload,
    String? messageId,
  }) async {
    consumeCalls.add(
      RecentNotificationGateCall(payload: payload, messageId: messageId),
    );
    return super.consumeIfRecentAnnouncement(
      payload: payload,
      messageId: messageId,
    );
  }
}
