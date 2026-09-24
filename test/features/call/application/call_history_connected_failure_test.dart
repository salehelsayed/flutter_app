import 'package:flutter_app/features/call/application/call_history_projector.dart';
import 'package:flutter_app/features/call/data/call_history_repository.dart';
import 'package:flutter_app/features/call/domain/call_end_reason.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// Beta 2026-09-24: a call that talked for ~3 minutes and then lost media
/// showed "Call failed" with no duration. A call that connected is a call
/// that happened; its row keeps its talk time whatever ended it.
final class _Repository implements CallHistoryRepository {
  final Map<CallId, CallHistoryEntry> rows = <CallId, CallHistoryEntry>{};

  @override
  Future<CallHistoryEntry?> getByCallId(CallId callId) async => rows[callId];

  @override
  Future<List<CallHistoryEntry>> listForContact(String peerId) async =>
      rows.values.toList();

  @override
  Future<void> upsertTerminal(CallHistoryEntry entry) async {
    rows.putIfAbsent(entry.callId, () => entry);
  }
}

CallSessionSnapshot _ended({
  required CallEndReason reason,
  required DateTime? connectedAt,
  CallDirection direction = CallDirection.outgoing,
}) {
  final startedAt = DateTime.utc(2026, 9, 24, 22, 57);
  return CallSessionSnapshot.active(
    callId: CallId.parse('33333333-3333-4333-8333-333333333333'),
    contactPeerId: 'contact-a',
    direction: direction,
    state: CallState.ended,
    callerAccountPeerId: direction == CallDirection.outgoing
        ? 'local-account'
        : 'contact-a',
    callerDeviceId: direction == CallDirection.outgoing
        ? 'local-device'
        : 'contact-device',
    startedAt: startedAt,
    connectedAt: connectedAt,
    endedAt: DateTime.utc(2026, 9, 24, 23, 0, 12),
    endReason: reason,
  );
}

void main() {
  const failures = <CallEndReason>[
    CallEndReason.mediaFailed,
    CallEndReason.reconnectFailed,
    CallEndReason.signalingFailed,
    CallEndReason.permissionDenied,
    CallEndReason.unsupported,
    CallEndReason.policyRejected,
  ];

  for (final reason in failures) {
    test('BETA-0924-10 a connected call ended by ${reason.wireName} is a '
        'completed call with its duration', () async {
      final connectedAt = DateTime.utc(2026, 9, 24, 22, 57, 7);
      final entry = await CallHistoryProjector(
        _Repository(),
      ).projectTerminal(_ended(reason: reason, connectedAt: connectedAt));

      expect(entry.status, CallHistoryStatus.completed);
      expect(entry.terminalReason, reason);
      expect(entry.duration, const Duration(minutes: 3, seconds: 5));
    });

    test('BETA-0924-11 a never-connected call ended by ${reason.wireName} '
        'is still a failed call', () async {
      final entry = await CallHistoryProjector(
        _Repository(),
      ).projectTerminal(_ended(reason: reason, connectedAt: null));

      expect(entry.status, CallHistoryStatus.failed);
      expect(entry.duration, isNull);
    });
  }
}
