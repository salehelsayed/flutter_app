import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/call/application/ringing_call_mailbox_poller.dart';
import 'package:flutter_app/features/call/domain/call_end_reason.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';

/// 407: drain the call mailbox while a call rings.
///
/// The relay skips the wake push for a recipient it considers attached — it
/// acked an earlier event of the same call, so its live connection is assumed
/// to carry the rest (`recipientAttached`, go-relay-server/
/// call_control_redis.go:736). Device 2026-09-05 21:21:05Z: the caller's
/// terminate stored with `wake: "none"` and every direct leg failed, so the
/// ringing iPhone never learned the call was cancelled and rang for nine more
/// seconds until the user declined by hand. A ring-time drain closes that
/// hole wherever the live path fails, not only for this one cause.
void main() {
  CallSessionSnapshot snapshot({
    CallState state = CallState.ringing,
    CallDirection direction = CallDirection.incoming,
  }) => CallSessionSnapshot.active(
    callId: CallId.parse('a2f0a1d6-0000-4000-8000-000000000407'),
    contactPeerId: 'contact-a',
    direction: direction,
    state: state,
    callerAccountPeerId: direction == CallDirection.outgoing
        ? 'local-account'
        : 'contact-a',
    callerDeviceId: direction == CallDirection.outgoing
        ? 'local-device'
        : 'contact-device',
    startedAt: DateTime.utc(2026, 2, 9, 15, 30),
    endedAt: state == CallState.ended ? DateTime.utc(2026, 2, 9, 15, 31) : null,
    endReason: state == CallState.ended ? CallEndReason.callerCancelled : null,
  );

  ({
    RingingCallMailboxPoller poller,
    _FakeScheduler scheduler,
    List<int> drains,
  })
  build({Object? drainError, Completer<void>? gate}) {
    final drains = <int>[];
    final scheduler = _FakeScheduler();
    var count = 0;
    final poller = RingingCallMailboxPoller(
      drain: () async {
        drains.add(++count);
        if (gate != null) await gate.future;
        if (drainError != null) throw drainError;
      },
      interval: const Duration(seconds: 2),
      schedule: scheduler.schedule,
    );
    return (poller: poller, scheduler: scheduler, drains: drains);
  }

  test('TC-407-01 a ringing call starts the drain timer', () {
    final rig = build();

    rig.poller.onSession(snapshot());

    expect(rig.scheduler.started, 1);
    expect(rig.scheduler.interval, const Duration(seconds: 2));
    expect(
      rig.drains,
      isEmpty,
      reason: 'the wake path already drained on presentation',
    );
  });

  test('TC-407-02 each tick drains the mailbox once', () async {
    final rig = build();
    rig.poller.onSession(snapshot());

    // Real ticks are an interval apart; back-to-back synchronous ticks are
    // what TC-407-08 asserts get collapsed.
    rig.scheduler.tick();
    await Future<void>.delayed(Duration.zero);
    rig.scheduler.tick();
    await Future<void>.delayed(Duration.zero);

    expect(rig.drains, <int>[1, 2]);
  });

  test('TC-407-03 an outgoing ringing call polls too: the callee reject can '
      'be skipped the same way', () {
    final rig = build();

    rig.poller.onSession(snapshot(direction: CallDirection.outgoing));

    expect(rig.scheduler.started, 1);
  });

  test('TC-407-04 ending the call stops the timer', () {
    final rig = build();
    rig.poller.onSession(snapshot());
    expect(rig.scheduler.cancelled, 0);

    rig.poller.onSession(snapshot(state: CallState.ended));

    expect(rig.scheduler.cancelled, 1);
  });

  test('TC-407-05 a null session stops the timer', () {
    final rig = build();
    rig.poller.onSession(snapshot());

    rig.poller.onSession(null);

    expect(rig.scheduler.cancelled, 1);
  });

  test('TC-407-06 idle and ended sessions never start a timer', () {
    final rig = build();

    rig.poller.onSession(CallSessionSnapshot.idle(now: DateTime.utc(2026)));
    rig.poller.onSession(snapshot(state: CallState.ended));

    expect(rig.scheduler.started, 0);
  });

  test(
    'acceptance, negotiation and recovery retain one mailbox drain',
    () async {
      final rig = build();
      rig.poller.onSession(snapshot());
      for (final state in [
        CallState.accepted,
        CallState.negotiating,
        CallState.connected,
        CallState.reconnecting,
      ]) {
        rig.poller.onSession(snapshot(state: state));
        rig.scheduler.tick();
        await Future<void>.delayed(Duration.zero);
      }
      expect(rig.drains, [1, 2, 3, 4]);
      expect(rig.scheduler.started, 1);
      expect(rig.scheduler.cancelled, 0);
      rig.poller.dispose();
    },
  );

  test('TC-407-07 staying ringing does not restart the timer', () {
    final rig = build();

    rig.poller.onSession(snapshot());
    rig.poller.onSession(snapshot());
    rig.poller.onSession(snapshot());

    expect(rig.scheduler.started, 1);
    expect(rig.scheduler.cancelled, 0);
  });

  test('TC-407-08 a slow drain never stacks a second one', () async {
    final gate = Completer<void>();
    final rig = build(gate: gate);
    rig.poller.onSession(snapshot());

    rig.scheduler.tick();
    await Future<void>.delayed(Duration.zero);
    rig.scheduler.tick();
    await Future<void>.delayed(Duration.zero);

    expect(rig.drains, <int>[1], reason: 'the first drain is still in flight');
    gate.complete();
    await Future<void>.delayed(Duration.zero);

    rig.scheduler.tick();
    await Future<void>.delayed(Duration.zero);
    expect(rig.drains, <int>[1, 2]);
  });

  test('TC-407-09 a throwing drain keeps the timer polling', () async {
    final rig = build(drainError: StateError('relay unavailable'));
    rig.poller.onSession(snapshot());

    rig.scheduler.tick();
    await Future<void>.delayed(Duration.zero);
    rig.scheduler.tick();
    await Future<void>.delayed(Duration.zero);

    expect(rig.drains, <int>[1, 2]);
    expect(rig.scheduler.cancelled, 0);
  });

  test('TC-407-10 dispose stops the timer', () {
    final rig = build();
    rig.poller.onSession(snapshot());

    rig.poller.dispose();

    expect(rig.scheduler.cancelled, 1);
  });
}

class _FakeScheduler {
  int started = 0;
  int cancelled = 0;
  Duration? interval;
  void Function()? _onTick;

  RingingCallMailboxPollHandle schedule(
    Duration interval,
    void Function() onTick,
  ) {
    started++;
    this.interval = interval;
    _onTick = onTick;
    return RingingCallMailboxPollHandle(() {
      cancelled++;
      _onTick = null;
    });
  }

  void tick() => _onTick?.call();
}
