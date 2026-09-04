import 'package:flutter_app/features/call/application/call_cleanup_coordinator.dart';
import 'package:flutter_app/features/call/application/call_coordinator.dart';
import 'package:flutter_app/features/call/application/call_history_projector.dart';
import 'package:flutter_app/features/call/data/call_history_repository.dart';
import 'package:flutter_app/features/call/domain/call_event.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_test/flutter_test.dart';

final class _History implements CallHistoryRepository {
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

final class _Effects implements CallEffectExecutor {
  final List<CallEffectType> seen = <CallEffectType>[];

  @override
  Future<CallEvent?> execute(
    CallEffect effect,
    CallSessionSnapshot snapshot,
  ) async {
    seen.add(effect.type);
    return null;
  }
}

CallEvent _place(CallId id, {required String localAccount}) => CallEvent(
  type: CallEventType.place,
  eventId: 'place-${id.value}',
  occurredAt: DateTime.utc(2026, 8, 30, 12),
  callId: id,
  contactPeerId: 'same-contact',
  localAccountPeerId: localAccount,
  localDeviceId: 'local-device',
  remoteAccountPeerId: 'same-contact',
  remoteDeviceId: 'remote-device',
);

CallEvent _invite(
  CallId id, {
  String contact = 'same-contact',
  required String remoteAccount,
}) => CallEvent(
  type: CallEventType.remoteInvite,
  eventId: 'invite-${id.value}',
  occurredAt: DateTime.utc(2026, 8, 30, 12),
  callId: id,
  contactPeerId: contact,
  localAccountPeerId: 'local-account',
  localDeviceId: 'local-device',
  remoteAccountPeerId: remoteAccount,
  remoteDeviceId: 'remote-device',
);

CallCoordinator _build(_History history, _Effects effects) => CallCoordinator(
  reducer: const CallReducer(),
  cleanupCoordinator: CallCleanupCoordinator(const <CallCleanupStep>[]),
  historyProjector: CallHistoryProjector(history),
  effectExecutor: effects,
  clock: () => DateTime.utc(2026, 8, 30, 12),
  idSource: () => CallId.parse('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
);

void main() {
  test(
    'same-contact glare replaces the lexicographically losing leg',
    () async {
      final history = _History();
      final effects = _Effects();
      final coordinator = _build(history, effects);
      addTearDown(coordinator.dispose);
      final outgoing = CallId.parse('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
      final incoming = CallId.parse('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');

      await coordinator.dispatch(_place(outgoing, localAccount: 'z-account'));
      await coordinator.dispatch(_invite(incoming, remoteAccount: 'a-account'));

      expect(coordinator.activeSession?.callId, incoming);
      expect(coordinator.activeSession?.direction, CallDirection.incoming);
      expect(history.rows.containsKey(outgoing), isTrue);
      expect(history.rows, hasLength(1));
    },
  );

  test(
    'same-contact glare keeps the canonical existing outgoing leg',
    () async {
      final history = _History();
      final effects = _Effects();
      final coordinator = _build(history, effects);
      addTearDown(coordinator.dispose);
      final outgoing = CallId.parse('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
      final incoming = CallId.parse('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');

      await coordinator.dispatch(_place(outgoing, localAccount: 'a-account'));
      final reduction = await coordinator.dispatch(
        _invite(incoming, remoteAccount: 'z-account'),
      );

      expect(coordinator.activeSession?.callId, outgoing);
      expect(reduction.reason, CallReductionReason.glareCanonicalCallWon);
      expect(effects.seen, contains(CallEffectType.sendBusy));
    },
  );

  test('glare compares call id before conflicting account ordering', () async {
    final history = _History();
    final effects = _Effects();
    final coordinator = _build(history, effects);
    addTearDown(coordinator.dispose);
    final lowerOutgoingId = CallId.parse(
      '11111111-1111-4111-8111-111111111111',
    );
    final higherIncomingId = CallId.parse(
      'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
    );

    await coordinator.dispatch(
      _place(lowerOutgoingId, localAccount: 'z-account'),
    );
    final reduction = await coordinator.dispatch(
      _invite(higherIncomingId, remoteAccount: 'a-account'),
    );

    expect(coordinator.activeSession?.callId, lowerOutgoingId);
    expect(reduction.reason, CallReductionReason.glareCanonicalCallWon);
  });

  test(
    'unrelated second call is busy and cannot replace active call',
    () async {
      final history = _History();
      final effects = _Effects();
      final coordinator = _build(history, effects);
      addTearDown(coordinator.dispose);
      final active = CallId.parse('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
      final unrelated = CallId.parse('cccccccc-cccc-4ccc-8ccc-cccccccccccc');

      await coordinator.dispatch(_place(active, localAccount: 'local-account'));
      final reduction = await coordinator.dispatch(
        _invite(
          unrelated,
          contact: 'unrelated-contact',
          remoteAccount: 'unrelated-contact',
        ),
      );

      expect(reduction.decision, CallEventDecision.rejected);
      expect(reduction.reason, CallReductionReason.busy);
      expect(coordinator.activeSession?.callId, active);
      expect(effects.seen, contains(CallEffectType.sendBusy));
    },
  );
}
