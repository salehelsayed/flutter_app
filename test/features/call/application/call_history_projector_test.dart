import 'package:flutter_app/features/call/application/call_history_projector.dart';
import 'package:flutter_app/features/call/data/call_history_repository.dart';
import 'package:flutter_app/features/call/data/call_history_conversation_timeline_source.dart';
import 'package:flutter_app/features/call/domain/call_end_reason.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/call_timeline_row.dart';
import 'package:flutter_app/l10n/app_localizations_en.dart';
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
  DateTime? ringingAt,
  DateTime? acceptedAt,
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
  ringingAt: ringingAt,
  acceptedAt: acceptedAt,
  connectedAt: connectedAt,
  endedAt: startedAt.add(const Duration(seconds: 5)),
  endReason: reason,
);

void main() {
  for (final (ringing, accepted, expectedStatus, expectedLabel) in [
    (false, false, CallHistoryStatus.failed, 'Call could not connect.'),
    (true, false, CallHistoryStatus.missed, 'No answer'),
    (false, true, CallHistoryStatus.missed, 'No answer'),
  ]) {
    test('CALL-PROGRESS history preserves no-answer evidence '
        'ringing=$ringing accepted=$accepted', () async {
      final started = DateTime.utc(2026, 11, 1, 12);
      final repository = _Repository();
      final projector = CallHistoryProjector(repository);
      final entry = await projector.projectTerminal(
        _terminal(
          id: 'a2f0a1d6-0000-4000-8000-000000000046',
          direction: CallDirection.outgoing,
          reason: CallEndReason.noAnswer,
          startedAt: started,
          ringingAt: ringing ? started : null,
          acceptedAt: accepted ? started : null,
        ),
      );

      expect(entry.status, expectedStatus);
      expect(entry.terminalReason, CallEndReason.noAnswer);
      final restored = CallHistoryEntry.fromMap(entry.toMap());
      expect(
        callTimelineStatusLabel(
          projectCallTimelineEntry(restored),
          AppLocalizationsEn(),
        ),
        expectedLabel,
      );
    });
  }

  test('CALL-PROGRESS legacy missed rows are not reinterpreted from absent '
      'milestones', () async {
    final started = DateTime.utc(2026, 11, 1, 12);
    final id = CallId.parse('a2f0a1d6-0000-4000-8000-000000000047');
    final repository = _Repository();
    repository.rows[id] = CallHistoryEntry(
      callId: id,
      contactAccountPeerId: 'contact-a',
      direction: CallDirection.outgoing,
      terminalReason: CallEndReason.noAnswer,
      status: CallHistoryStatus.missed,
      startedAt: started,
      endedAt: started.add(const Duration(seconds: 5)),
      transportRoute: null,
      createdAt: started,
      updatedAt: started,
    );
    final entry = await CallHistoryProjector(repository).projectTerminal(
      _terminal(
        id: id.value,
        direction: CallDirection.outgoing,
        reason: CallEndReason.noAnswer,
        startedAt: started,
      ),
    );
    expect(entry.status, CallHistoryStatus.missed);
    expect(
      callTimelineStatusLabel(
        projectCallTimelineEntry(entry),
        AppLocalizationsEn(),
      ),
      'No answer',
    );
  });

  test(
    'CALL-PROGRESS incoming no-answer still records a missed call',
    () async {
      final entry = await CallHistoryProjector(_Repository()).projectTerminal(
        _terminal(
          id: 'a2f0a1d6-0000-4000-8000-000000000048',
          direction: CallDirection.incoming,
          reason: CallEndReason.noAnswer,
          startedAt: DateTime.utc(2026, 11, 1, 12),
        ),
      );
      expect(entry.status, CallHistoryStatus.missed);
      expect(
        callTimelineStatusLabel(
          projectCallTimelineEntry(entry),
          AppLocalizationsEn(),
        ),
        'Missed voice call',
      );
    },
  );

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

  test(
    'terminal reasons map to stable privacy-safe history statuses',
    () async {
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
          CallEndReason.remotePermissionDenied,
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
        (
          CallDirection.incoming,
          CallEndReason.expired,
          CallHistoryStatus.missed,
        ),
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
        final id =
            '00000000-0000-4000-8000-${index.toString().padLeft(12, '0')}';
        final entry = await projector.projectTerminal(
          _terminal(
            id: id,
            direction: value.$1,
            reason: value.$2,
            startedAt: DateTime.utc(2026, 8, 30, 12, index),
            ringingAt: value.$2 == CallEndReason.noAnswer
                ? DateTime.utc(2026, 8, 30, 12, index)
                : null,
          ),
        );
        expect(entry.status, value.$3, reason: value.$2.name);
      }
    },
  );

  test('a callee that could not present the call keeps a busy row', () async {
    final projector = CallHistoryProjector(_Repository());

    final entry = await projector.projectTerminal(
      _terminal(
        id: 'b0b0b0b0-b0b0-4b0b-8b0b-b0b0b0b0b0b0',
        direction: CallDirection.incoming,
        reason: CallEndReason.busy,
        startedAt: DateTime.utc(2026, 10, 15, 20),
      ),
    );

    expect(entry.status, CallHistoryStatus.busy);
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
