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

final class _PairedEffects implements CallEffectExecutor {
  final presented = <CallId>[];
  @override
  Future<CallEvent?> execute(
    CallEffect effect,
    CallSessionSnapshot snapshot,
  ) async {
    final type = switch (effect.type) {
      CallEffectType.prepareOutgoingInvite => CallEventType.outgoingInviteReady,
      CallEffectType.validateIncomingInvite => CallEventType.incomingValidated,
      CallEffectType.presentIncomingCall => CallEventType.systemUiPresented,
      _ => null,
    };
    if (effect.type == CallEffectType.presentIncomingCall) {
      presented.add(snapshot.callId!);
    }
    return type == null
        ? null
        : CallEvent(
            type: type,
            eventId: '${type.name}-${snapshot.callId!.value}',
            occurredAt: DateTime.utc(2026, 8, 30, 12),
            callId: snapshot.callId,
          );
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
  for (final lowerSide in ['a', 'b']) {
    for (final reverse in [false, true]) {
      test(
        'paired glare converges with lower caller $lowerSide and reversed delivery $reverse, terminal replay cleans once',
        () async {
          final now = DateTime.utc(2026, 8, 30, 12);
          final lower = CallId.parse('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
          final higher = CallId.parse('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
          final ids = {
            'a': lowerSide == 'a' ? lower : higher,
            'b': lowerSide == 'b' ? lower : higher,
          };
          final histories = {'a': _History(), 'b': _History()};
          final effects = {'a': _PairedEffects(), 'b': _PairedEffects()};
          final cleanup = <String, Map<CallId, int>>{'a': {}, 'b': {}};
          final peers = <String, CallCoordinator>{};
          for (final side in ['a', 'b']) {
            peers[side] = CallCoordinator(
              reducer: const CallReducer(),
              cleanupCoordinator: CallCleanupCoordinator([
                CallCleanupStep('media', (s) async {
                  cleanup[side]!.update(
                    s.callId!,
                    (n) => n + 1,
                    ifAbsent: () => 1,
                  );
                }),
              ]),
              historyProjector: CallHistoryProjector(histories[side]!),
              effectExecutor: effects[side]!,
              clock: () => now,
              idSource: () => ids[side]!,
            );
            addTearDown(peers[side]!.dispose);
            final other = side == 'a' ? 'b' : 'a';
            await peers[side]!.dispatch(
              CallEvent(
                type: CallEventType.place,
                eventId: '$side-place',
                occurredAt: now,
                callId: ids[side],
                contactPeerId: other,
                localAccountPeerId: side,
                localDeviceId: '$side-device',
                remoteAccountPeerId: other,
                remoteDeviceId: '$other-device',
              ),
            );
          }
          for (final side in reverse ? ['b', 'a'] : ['a', 'b']) {
            final other = side == 'a' ? 'b' : 'a';
            final invite = CallEvent(
              type: CallEventType.remoteInvite,
              eventId: '$side-invite',
              occurredAt: now,
              callId: ids[other],
              contactPeerId: other,
              localAccountPeerId: side,
              localDeviceId: '$side-device',
              remoteAccountPeerId: other,
              remoteDeviceId: '$other-device',
              expiresAt: now.add(const Duration(seconds: 40)),
            );
            await peers[side]!.dispatch(invite);
            await peers[side]!.dispatch(invite);
          }
          expect(
            peers.values.map((p) => p.activeSession?.callId),
            everyElement(lower),
          );
          expect(effects.values.expand((e) => e.presented), [lower]);
          for (final side in ['a', 'b']) {
            await peers[side]!.dispatch(
              CallEvent(
                type: CallEventType.remoteTerminate,
                eventId: '$side-loser-terminal',
                occurredAt: now,
                callId: higher,
              ),
            );
            expect(peers[side]!.activeSession?.callId, lower);
            final terminal = CallEvent(
              type: CallEventType.remoteTerminate,
              eventId: '$side-winner-terminal',
              occurredAt: now,
              callId: lower,
            );
            await peers[side]!.dispatch(terminal);
            await peers[side]!.dispatch(terminal);
            expect(peers[side]!.activeSession, isNull);
            expect(cleanup[side]![lower], 1);
            expect(cleanup[side]!.values, everyElement(1));
            expect(
              histories[side]!.rows,
              hasLength(ids[side] == lower ? 1 : 2),
            );
          }
        },
      );
    }
  }
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
