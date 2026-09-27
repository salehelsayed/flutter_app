import 'package:flutter_app/features/call/application/call_history_projector.dart';
import 'package:flutter_app/features/call/data/call_history_repository.dart';
import 'package:flutter_app/features/call/domain/call_end_reason.dart';
import 'package:flutter_app/features/call/domain/call_event.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// Beta 2026-09-24: a terminate carries the SENDER's end reason. The receiver
/// must read it from its own side, or a caller's hang-up shows up on the
/// callee as "You declined".
final _callA = CallId.parse('22222222-2222-4222-8222-222222222222');
final _t0 = DateTime.utc(2026, 9, 24, 23);

CallEvent _event(
  CallEventType type, {
  String? eventId,
  CallNativeAction? nativeAction,
  CallEndReason? endReason,
}) => CallEvent(
  type: type,
  eventId: eventId ?? '${type.name}-event',
  occurredAt: _t0,
  callId: _callA,
  contactPeerId: 'contact-account-a',
  localAccountPeerId: 'local-account',
  localDeviceId: 'local-device',
  remoteAccountPeerId: 'contact-account-a',
  remoteDeviceId: 'contact-device-a',
  admission: IncomingCallAdmission.accepted,
  nativeAction: nativeAction,
  endReason: endReason,
);

CallSessionSnapshot _reduce(List<CallEvent> events) {
  const reducer = CallReducer();
  var snapshot = CallSessionSnapshot.idle(now: _t0);
  for (final event in events) {
    snapshot = reducer.reduce(snapshot, event).snapshot;
  }
  return snapshot;
}

final _incomingRinging = <CallEvent>[
  _event(CallEventType.remoteInvite),
  _event(CallEventType.incomingValidated),
  _event(CallEventType.systemUiPresented),
];

final _outgoingRinging = <CallEvent>[
  _event(CallEventType.place),
  _event(CallEventType.outgoingInviteReady),
  _event(CallEventType.remoteRinging),
];

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

void main() {
  group('remote terminate reads the reason from the receiver side', () {
    test('BETA-0924-01 a ringing callee reads the caller local_hangup as a '
        'remote hang-up and records a missed call', () async {
      final ended = _reduce(<CallEvent>[
        ..._incomingRinging,
        _event(
          CallEventType.remoteTerminate,
          endReason: CallEndReason.localHangup,
        ),
      ]);

      expect(ended.state, CallState.ended);
      expect(ended.endReason, CallEndReason.remoteHangup);
      final entry = await CallHistoryProjector(
        _Repository(),
      ).projectTerminal(ended);
      expect(entry.status, CallHistoryStatus.missed);
    });

    test('BETA-0924-02 a connected peer reads local_hangup as a remote '
        'hang-up and keeps the completed row', () async {
      final ended = _reduce(<CallEvent>[
        ..._outgoingRinging,
        _event(CallEventType.remoteAccept),
        _event(CallEventType.negotiationReady),
        _event(CallEventType.mediaConnected),
        _event(
          CallEventType.remoteTerminate,
          endReason: CallEndReason.localHangup,
        ),
      ]);

      expect(ended.endReason, CallEndReason.remoteHangup);
      final entry = await CallHistoryProjector(
        _Repository(),
      ).projectTerminal(ended);
      expect(entry.status, CallHistoryStatus.completed);
    });

    for (final reason in <CallEndReason>[
      CallEndReason.callerCancelled,
      CallEndReason.noAnswer,
      CallEndReason.expired,
      CallEndReason.mediaFailed,
    ]) {
      test(
        'BETA-0924-03 a shared-meaning reason ${reason.wireName} is kept',
        () {
          final ended = _reduce(<CallEvent>[
            ..._incomingRinging,
            _event(CallEventType.remoteTerminate, endReason: reason),
          ]);
          expect(ended.endReason, reason);
        },
      );
    }

    test(
      'BETA-0924-04 a terminate without a reason stays a remote hang-up',
      () {
        final ended = _reduce(<CallEvent>[
          ..._incomingRinging,
          _event(CallEventType.remoteTerminate),
        ]);
        expect(ended.endReason, CallEndReason.remoteHangup);
      },
    );
  });

  group('caller native end before connect is a caller cancel', () {
    test('BETA-0924-05 an outgoing ringing call ended from the system UI is '
        'recorded and sent as caller_cancelled', () {
      const reducer = CallReducer();
      final ringing = _reduce(_outgoingRinging);

      final reduction = reducer.reduce(
        ringing,
        _event(
          CallEventType.nativeAction,
          eventId: 'native-end',
          nativeAction: CallNativeAction.end,
        ),
      );

      expect(reduction.snapshot.endReason, CallEndReason.callerCancelled);
      expect(
        reduction.effects.map((effect) => effect.type),
        contains(CallEffectType.sendTerminate),
      );
    });

    test('BETA-0924-06 a connected outgoing call ended from the system UI '
        'stays a local hang-up', () {
      final ended = _reduce(<CallEvent>[
        ..._outgoingRinging,
        _event(CallEventType.remoteAccept),
        _event(CallEventType.negotiationReady),
        _event(CallEventType.mediaConnected),
        _event(
          CallEventType.nativeAction,
          eventId: 'native-end',
          nativeAction: CallNativeAction.end,
        ),
      ]);
      expect(ended.endReason, CallEndReason.localHangup);
    });

    test('BETA-0924-07 a ringing callee ended from the system UI keeps '
        'local_hangup (it declined)', () {
      final ended = _reduce(<CallEvent>[
        ..._incomingRinging,
        _event(
          CallEventType.nativeAction,
          eventId: 'native-end',
          nativeAction: CallNativeAction.end,
        ),
      ]);
      expect(ended.endReason, CallEndReason.localHangup);
    });
  });
}
