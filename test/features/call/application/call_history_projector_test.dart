import 'package:flutter_app/features/call/application/call_history_projector.dart';
import 'package:flutter_app/features/call/data/call_history_repository.dart';
import 'package:flutter_app/features/call/domain/call_end_reason.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Repository implements CallHistoryRepository {
  final Map<CallId, CallHistoryEntry> rows = <CallId, CallHistoryEntry>{};

  @override
  Future<CallHistoryEntry?> getByCallId(CallId callId) async => rows[callId];

  @override
  Future<List<CallHistoryEntry>> listForContact(String peerId) async => rows
      .values
      .where((entry) => entry.contactAccountPeerId == peerId)
      .toList();

  @override
  Future<void> upsertTerminal(CallHistoryEntry entry) async {
    rows.putIfAbsent(entry.callId, () => entry);
  }
}

CallSessionSnapshot _terminal({
  required String id,
  required CallDirection direction,
  required CallEndReason reason,
  required DateTime startedAt,
  DateTime? connectedAt,
}) => CallSessionSnapshot.active(
  callId: CallId.parse(id),
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
  endedAt: startedAt.add(const Duration(seconds: 5)),
  endReason: reason,
);

void main() {
  test('TC-405-43 a projected terminal call announces itself once', () async {
    final announced = <bool>[];
    final projector = CallHistoryProjector(
      _Repository(),
      onTerminalProjected: (_, inserted) => announced.add(inserted),
    );
    final snapshot = _terminal(
      id: 'a2f0a1d6-0000-4000-8000-000000000043',
      direction: CallDirection.outgoing,
      reason: CallEndReason.callerCancelled,
      startedAt: DateTime.utc(2026, 2, 9, 15, 30),
    );

    await projector.projectTerminal(snapshot);

    expect(
      announced,
      <bool>[true],
      reason:
          'the chat re-reads the table on this signal; without it a call taken '
          'from inside the conversation leaves the screen mounted and stale',
    );
  });

  test('TC-405-44 a replayed terminal call still announces, so a late '
      'listener converges', () async {
    final announced = <bool>[];
    final projector = CallHistoryProjector(
      _Repository(),
      onTerminalProjected: (_, inserted) => announced.add(inserted),
    );
    final snapshot = _terminal(
      id: 'a2f0a1d6-0000-4000-8000-000000000044',
      direction: CallDirection.incoming,
      reason: CallEndReason.declined,
      startedAt: DateTime.utc(2026, 2, 9, 15, 30),
    );

    await projector.projectTerminal(snapshot);
    await projector.projectTerminal(snapshot);

    expect(announced, <bool>[true, false]);
  });

  test('TC-405-45 a throwing listener never breaks the projection', () async {
    final repository = _Repository();
    final projector = CallHistoryProjector(
      repository,
      onTerminalProjected: (_, _) => throw StateError('listener exploded'),
    );
    final snapshot = _terminal(
      id: 'a2f0a1d6-0000-4000-8000-000000000045',
      direction: CallDirection.outgoing,
      reason: CallEndReason.localHangup,
      startedAt: DateTime.utc(2026, 2, 9, 15, 30),
    );

    final entry = await projector.projectTerminal(snapshot);

    expect(entry.status, CallHistoryStatus.cancelled);
    expect(repository.rows, hasLength(1));
  });

  test('history status enum preserves the exact frozen product grammar', () {
    expect(CallHistoryStatus.values.map((status) => status.wireName), <String>[
      'completed',
      'missed',
      'declined',
      'busy',
      'cancelled',
      'failed',
    ]);
  });

  test('terminal reasons map to stable privacy-safe history statuses', () async {
    final repository = _Repository();
    final projector = CallHistoryProjector(repository);
    final cases = <(CallDirection, CallEndReason, CallHistoryStatus)>[
      (
        CallDirection.incoming,
        CallEndReason.declined,
        CallHistoryStatus.declined,
      ),
      (CallDirection.outgoing, CallEndReason.busy, CallHistoryStatus.busy),
      (
        CallDirection.outgoing,
        CallEndReason.callerCancelled,
        CallHistoryStatus.cancelled,
      ),
      (
        CallDirection.outgoing,
        CallEndReason.noAnswer,
        CallHistoryStatus.missed,
      ),
      // Hangups before media connected (no connectedAt in this table).
      (
        CallDirection.outgoing,
        CallEndReason.remoteHangup,
        CallHistoryStatus.declined,
      ),
      (
        CallDirection.incoming,
        CallEndReason.remoteHangup,
        CallHistoryStatus.missed,
      ),
      (
        CallDirection.incoming,
        CallEndReason.localHangup,
        CallHistoryStatus.declined,
      ),
      (
        CallDirection.outgoing,
        CallEndReason.localHangup,
        CallHistoryStatus.cancelled,
      ),
      (
        CallDirection.outgoing,
        CallEndReason.permissionDenied,
        CallHistoryStatus.failed,
      ),
      (
        CallDirection.outgoing,
        CallEndReason.unsupported,
        CallHistoryStatus.failed,
      ),
      (
        CallDirection.outgoing,
        CallEndReason.signalingFailed,
        CallHistoryStatus.failed,
      ),
      (
        CallDirection.outgoing,
        CallEndReason.mediaFailed,
        CallHistoryStatus.failed,
      ),
      (
        CallDirection.outgoing,
        CallEndReason.reconnectFailed,
        CallHistoryStatus.failed,
      ),
      (CallDirection.incoming, CallEndReason.expired, CallHistoryStatus.missed),
      (
        CallDirection.outgoing,
        CallEndReason.appShutdown,
        CallHistoryStatus.failed,
      ),
      (
        CallDirection.outgoing,
        CallEndReason.policyRejected,
        CallHistoryStatus.failed,
      ),
    ];

    for (var index = 0; index < cases.length; index++) {
      final value = cases[index];
      final hex = index.toRadixString(16);
      final id =
          '$hex$hex$hex$hex$hex$hex$hex$hex-$hex$hex$hex$hex-4$hex$hex$hex-8$hex$hex$hex-$hex$hex$hex$hex$hex$hex$hex$hex$hex$hex$hex$hex';
      final entry = await projector.projectTerminal(
        _terminal(
          id: id,
          direction: value.$1,
          reason: value.$2,
          startedAt: DateTime.utc(2026, 8, 30, 12, index),
        ),
      );
      expect(entry.status, value.$3, reason: value.$2.name);
    }
  });

  test('hangups after media connected are completed calls', () async {
    final repository = _Repository();
    final projector = CallHistoryProjector(repository);
    for (final (index, value) in <(CallDirection, CallEndReason)>[
      (CallDirection.outgoing, CallEndReason.localHangup),
      (CallDirection.incoming, CallEndReason.localHangup),
      (CallDirection.outgoing, CallEndReason.remoteHangup),
      (CallDirection.incoming, CallEndReason.remoteHangup),
    ].indexed) {
      final hex = (index + 4).toRadixString(16);
      final id =
          '$hex$hex$hex$hex$hex$hex$hex$hex-$hex$hex$hex$hex-4$hex$hex$hex-8$hex$hex$hex-$hex$hex$hex$hex$hex$hex$hex$hex$hex$hex$hex$hex';
      final entry = await projector.projectTerminal(
        _terminal(
          id: id,
          direction: value.$1,
          reason: value.$2,
          startedAt: DateTime.utc(2026, 8, 30, 13, index),
          connectedAt: DateTime.utc(2026, 8, 30, 13, index, 5),
        ),
      );
      expect(entry.status, CallHistoryStatus.completed, reason: value.$2.name);
    }
  });

  test(
    'conversation timeline is oldest first with stable call-id tie break',
    () async {
      final repository = _Repository();
      final projector = CallHistoryProjector(repository);
      final sameTime = DateTime.utc(2026, 8, 30, 12);
      await projector.projectTerminal(
        _terminal(
          id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
          direction: CallDirection.outgoing,
          reason: CallEndReason.callerCancelled,
          startedAt: sameTime,
        ),
      );
      await projector.projectTerminal(
        _terminal(
          id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          direction: CallDirection.incoming,
          reason: CallEndReason.expired,
          startedAt: sameTime,
        ),
      );
      await projector.projectTerminal(
        _terminal(
          id: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
          direction: CallDirection.outgoing,
          reason: CallEndReason.localHangup,
          startedAt: sameTime.add(const Duration(minutes: 1)),
          connectedAt: sameTime.add(const Duration(minutes: 1)),
        ),
      );

      final timeline = await projector.timelineForContact('contact-a');
      expect(timeline.map((entry) => entry.callId.value), <String>[
        'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
        'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
      ]);
    },
  );
}
