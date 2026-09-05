import 'dart:async';

import 'package:flutter_app/features/call/application/call_control_effect_executor.dart';
import 'package:flutter_app/features/call/application/call_cleanup_coordinator.dart';
import 'package:flutter_app/features/call/application/call_coordinator.dart';
import 'package:flutter_app/features/call/application/call_history_projector.dart';
import 'package:flutter_app/features/call/application/call_signaling_context_store.dart';
import 'package:flutter_app/features/call/data/call_history_repository.dart';
import 'package:flutter_app/features/call/domain/call_end_reason.dart';
import 'package:flutter_app/features/call/domain/call_event.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/call/domain/call_signal.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_test/flutter_test.dart';

final _callId = CallId.parse('55555555-5555-4555-8555-555555555555');
final _busyCallId = CallId.parse('66666666-6666-4666-8666-666666666666');
final _now = DateTime.utc(2026, 8, 30, 12);

CallSessionSnapshot _outgoing(CallState state) => CallSessionSnapshot.active(
  callId: _callId,
  contactPeerId: 'remote-account',
  direction: CallDirection.outgoing,
  state: state,
  callerAccountPeerId: 'local-account',
  callerDeviceId: 'local-device',
  startedAt: _now,
  observedAt: _now,
);

CallSessionSnapshot _endedOutgoing({
  CallEndReason endReason = CallEndReason.callerCancelled,
}) => CallSessionSnapshot.active(
  callId: _callId,
  contactPeerId: 'remote-account',
  direction: CallDirection.outgoing,
  state: CallState.ended,
  callerAccountPeerId: 'local-account',
  callerDeviceId: 'local-device',
  startedAt: _now,
  observedAt: _now,
  endedAt: _now,
  endReason: endReason,
);

CallSessionSnapshot _incoming(CallState state, {CallEndReason? endReason}) =>
    CallSessionSnapshot.active(
      callId: _callId,
      contactPeerId: 'remote-account',
      direction: CallDirection.incoming,
      state: state,
      callerAccountPeerId: 'remote-account',
      callerDeviceId: 'remote-device',
      startedAt: _now,
      observedAt: _now,
      acceptedAt: state == CallState.accepted ? _now : null,
      endedAt: state == CallState.ended ? _now : null,
      endReason: endReason,
    );

CallSignal _authenticatedInvite(CallId callId) => CallSignal.create(
  callId: callId,
  messageId: callId == _callId
      ? '77777777-7777-4777-8777-777777777777'
      : '88888888-8888-4888-8888-888888888888',
  event: CallSignalType.invite,
  senderAccountPeerId: callId == _callId
      ? 'remote-account'
      : 'busy-remote-account',
  senderDevicePeerId: callId == _callId
      ? 'remote-device'
      : 'busy-remote-device',
  recipientAccountPeerId: 'local-account',
  recipientDevicePeerId: 'local-device',
  senderSequence: 1,
  iceGeneration: 0,
  createdAtMs: _now.millisecondsSinceEpoch,
  expiresAtMs: _now.millisecondsSinceEpoch + 45_000,
);

void main() {
  test(
    'one canonical coordinator consumes prepare and custody follow-ups in lane',
    () async {
      final port = _Port(
        result: CallControlSendResult(
          directAccepted: true,
          mailboxStored: true,
          directRoute: CallRouteClass.direct,
          mailboxStoreSettled: Future<void>.value(),
        ),
      );
      final store = CallSignalingContextStore();
      final control = _executor(port, store);
      final negotiation = _RecordingExecutor();
      final coordinator = CallCoordinator(
        reducer: const CallReducer(),
        cleanupCoordinator: CallCleanupCoordinator(const <CallCleanupStep>[]),
        historyProjector: CallHistoryProjector(_History()),
        effectExecutor: CompositeCallEffectExecutor(
          controlExecutor: control,
          negotiationExecutor: negotiation,
        ),
        clock: () => _now,
        idSource: () => _callId,
      );
      addTearDown(coordinator.dispose);

      await coordinator.dispatch(
        CallEvent(
          type: CallEventType.place,
          eventId: 'place-call',
          occurredAt: _now,
          callId: _callId,
          contactPeerId: 'remote-account',
          localAccountPeerId: 'local-account',
          localDeviceId: 'local-device',
        ),
      );

      expect(coordinator.activeSession?.state, CallState.inviting);
      expect(coordinator.activeSession?.mailboxCustodyConfirmed, isTrue);
      expect(port.prepareCalls, 1);
      expect(port.signals, hasLength(1));
      expect(port.signals.single.event, CallSignalType.invite);
      expect(negotiation.effects, isEmpty);
    },
  );

  test(
    'a dispatched wake turns the mailbox custody follow-up into ringing',
    () async {
      // The relay alerted the callee's device; a headless callee signals
      // nothing until it is answered, so the caller rings back on this
      // receipt (device 2026-09-05: no ringback when calling a dead Pixel).
      final port = _Port(
        result: CallControlSendResult(
          directAccepted: false,
          mailboxStored: true,
          wakeDispatched: true,
          mailboxStoreSettled: Future<void>.value(),
        ),
      );
      final store = CallSignalingContextStore();
      final control = _executor(port, store);
      final negotiation = _RecordingExecutor();
      final coordinator = CallCoordinator(
        reducer: const CallReducer(),
        cleanupCoordinator: CallCleanupCoordinator(const <CallCleanupStep>[]),
        historyProjector: CallHistoryProjector(_History()),
        effectExecutor: CompositeCallEffectExecutor(
          controlExecutor: control,
          negotiationExecutor: negotiation,
        ),
        clock: () => _now,
        idSource: () => _callId,
      );
      addTearDown(coordinator.dispose);
      await coordinator.dispatch(
        CallEvent(
          type: CallEventType.place,
          eventId: 'place-call',
          occurredAt: _now,
          callId: _callId,
          contactPeerId: 'remote-account',
          localAccountPeerId: 'local-account',
          localDeviceId: 'local-device',
        ),
      );
      expect(coordinator.activeSession?.state, CallState.ringing);
      expect(coordinator.activeSession?.mailboxCustodyConfirmed, isTrue);
      expect(coordinator.activeSession?.ringingAt, _now);
      expect(
        coordinator.activeSession?.recentEventIds,
        contains(startsWith('call-control-wakeRequested-')),
      );
      expect(port.signals.single.event, CallSignalType.invite);
    },
  );

  test(
    'applied foreground cancel sends authenticated caller-cancelled terminate',
    () async {
      final port = _Port();
      final store = CallSignalingContextStore();
      final retirements = <(String, String)>[];
      late final CallControlEffectExecutor control;
      final coordinator = CallCoordinator(
        reducer: const CallReducer(),
        cleanupCoordinator: CallCleanupCoordinator(<CallCleanupStep>[
          CallCleanupStep('call_signaling_context', (snapshot) async {
            await control.retireOutgoingPreconnectInvite(snapshot);
            store.purge(snapshot.callId!);
          }, requiredForTerminalAck: true),
        ]),
        historyProjector: CallHistoryProjector(_History()),
        effectExecutor: control = _executor(
          port,
          store,
          cancelOutgoingMailboxInvite:
              ({required recipientDevicePeerId, required callHandle}) async {
                expect(store.read(_callId), isNotNull);
                retirements.add((recipientDevicePeerId, callHandle));
                return true;
              },
        ),
        clock: () => _now,
        idSource: () => _callId,
      );
      addTearDown(coordinator.dispose);

      await coordinator.placeCall(
        contactPeerId: 'remote-account',
        localAccountPeerId: 'local-account',
        localDeviceId: 'local-device',
      );

      final reduction = await coordinator.dispatch(
        CallEvent(
          type: CallEventType.cancel,
          eventId: 'foreground-cancel-fixture',
          occurredAt: _now,
          callId: _callId,
          contactPeerId: 'remote-account',
        ),
      );

      expect(reduction.decision, CallEventDecision.applied);
      expect(reduction.snapshot.endReason, CallEndReason.callerCancelled);
      final terminate = port.signals.singleWhere(
        (signal) => signal.event == CallSignalType.terminate,
      );
      expect(terminate.callId, _callId);
      expect(terminate.senderAccountPeerId, 'local-account');
      expect(terminate.senderDevicePeerId, 'local-device');
      expect(terminate.recipientAccountPeerId, 'remote-account');
      expect(terminate.recipientDevicePeerId, 'remote-device');
      expect(terminate.payload, <String, Object?>{
        'reason': CallEndReason.callerCancelled.wireName,
      });
      expect(
        port.callHandles,
        everyElement('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
      );
      expect(retirements, <(String, String)>[
        ('remote-device', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
      ]);
      expect(store.read(_callId), isNull);
      expect(coordinator.terminalCleanupAckReady(_callId), isTrue);
    },
  );

  test('a mailbox-stored invite cancelled before ringing keeps the mailbox and '
      'stores the terminate after the invite settles', () async {
    final inviteSettled = Completer<void>();
    final order = <String>[];
    final port = _Port(
      onSend: (signal, callHandle) {
        order.add(signal.event.wireName);
        if (signal.event == CallSignalType.invite) {
          return Future<CallControlSendResult>.value(
            CallControlSendResult(
              directAccepted: false,
              mailboxStored: true,
              mailboxStoreSettled: inviteSettled.future,
            ),
          );
        }
        return Future<CallControlSendResult>.value(
          CallControlSendResult(
            directAccepted: false,
            mailboxStored: true,
            mailboxStoreSettled: Future<void>.value(),
          ),
        );
      },
    );
    final store = CallSignalingContextStore();
    final retirements = <String>[];
    late final CallControlEffectExecutor control;
    final coordinator = CallCoordinator(
      reducer: const CallReducer(),
      cleanupCoordinator: CallCleanupCoordinator(<CallCleanupStep>[
        CallCleanupStep('call_signaling_context', (snapshot) async {
          await control.retireOutgoingPreconnectInvite(snapshot);
          store.purge(snapshot.callId!);
        }, requiredForTerminalAck: true),
      ]),
      historyProjector: CallHistoryProjector(_History()),
      effectExecutor: control = _executor(
        port,
        store,
        cancelOutgoingMailboxInvite:
            ({required recipientDevicePeerId, required callHandle}) async {
              retirements.add(callHandle);
              return true;
            },
      ),
      clock: () => _now,
      idSource: () => _callId,
    );
    addTearDown(coordinator.dispose);

    await coordinator.placeCall(
      contactPeerId: 'remote-account',
      localAccountPeerId: 'local-account',
      localDeviceId: 'local-device',
    );
    expect(order, <String>['invite']);

    // The caller gives up before any ringing signal came back. The relay
    // already woke the callee natively for the invite, so the terminate
    // must land behind it instead of the mailbox being wiped.
    final cancel = coordinator.dispatch(
      CallEvent(
        type: CallEventType.cancel,
        eventId: 'cancel-before-ringing',
        occurredAt: _now,
        callId: _callId,
        contactPeerId: 'remote-account',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(order, <String>['invite'], reason: 'terminate waits for custody');

    inviteSettled.complete();
    final reduction = await cancel;

    expect(reduction.decision, CallEventDecision.applied);
    expect(order, <String>['invite', 'terminate']);
    expect(retirements, isEmpty);
    expect(store.read(_callId), isNull);
    expect(coordinator.terminalCleanupAckReady(_callId), isTrue);
  });

  test(
    'mailbox retirement waits for invite custody and coalesces duplicates',
    () async {
      final mailboxStoreSettled = Completer<void>();
      final order = <String>[];
      final port = _Port(
        onSend: (signal, callHandle) {
          if (signal.event != CallSignalType.invite) {
            return Future<CallControlSendResult>.value(
              CallControlSendResult(
                directAccepted: false,
                mailboxStored: true,
                mailboxStoreSettled: Future<void>.value(),
              ),
            );
          }
          return Future<CallControlSendResult>.value(
            CallControlSendResult(
              directAccepted: true,
              mailboxStored: false,
              directRoute: CallRouteClass.direct,
              mailboxStoreSettled: mailboxStoreSettled.future,
            ),
          );
        },
      );
      final store = CallSignalingContextStore();
      final executor = _executor(
        port,
        store,
        cancelOutgoingMailboxInvite:
            ({required recipientDevicePeerId, required callHandle}) async {
              expect(store.read(_callId), isNotNull);
              order.add('cancel');
              return true;
            },
      );
      await executor.execute(
        const CallEffect(CallEffectType.prepareOutgoingInvite),
        _outgoing(CallState.preparing),
      );

      final invite = executor.execute(
        const CallEffect(CallEffectType.sendInvite),
        _outgoing(CallState.inviting),
      );
      final firstRetirement = executor.retireOutgoingPreconnectInvite(
        _endedOutgoing(),
      );
      final duplicateRetirement = executor.retireOutgoingPreconnectInvite(
        _endedOutgoing(),
      );
      await Future<void>.delayed(Duration.zero);
      expect(order, isEmpty);

      await invite;
      expect(order, isEmpty);
      order.add('store');
      mailboxStoreSettled.complete();
      await Future.wait<void>(<Future<void>>[
        firstRetirement,
        duplicateRetirement,
      ]);
      await executor.retireOutgoingPreconnectInvite(_endedOutgoing());

      expect(order, <String>['store', 'cancel']);
    },
  );

  test(
    'terminate transport failure still retires one mailbox invitation',
    () async {
      final port = _Port(failSignalType: CallSignalType.terminate);
      final store = CallSignalingContextStore();
      var retirementCalls = 0;
      late final CallControlEffectExecutor control;
      final coordinator = CallCoordinator(
        reducer: const CallReducer(),
        cleanupCoordinator: CallCleanupCoordinator(<CallCleanupStep>[
          CallCleanupStep('call_signaling_context', (snapshot) async {
            await control.retireOutgoingPreconnectInvite(snapshot);
            store.purge(snapshot.callId!);
          }, requiredForTerminalAck: true),
        ]),
        historyProjector: CallHistoryProjector(_History()),
        effectExecutor: control = _executor(
          port,
          store,
          cancelOutgoingMailboxInvite:
              ({required recipientDevicePeerId, required callHandle}) async {
                retirementCalls++;
                return true;
              },
        ),
        clock: () => _now,
        idSource: () => _callId,
      );
      addTearDown(coordinator.dispose);
      await coordinator.placeCall(
        contactPeerId: 'remote-account',
        localAccountPeerId: 'local-account',
        localDeviceId: 'local-device',
      );

      final reduction = await coordinator.dispatch(
        CallEvent(
          type: CallEventType.cancel,
          eventId: 'cancel-with-failed-terminate',
          occurredAt: _now,
          callId: _callId,
          contactPeerId: 'remote-account',
        ),
      );

      expect(reduction.snapshot.isTerminal, isTrue);
      expect(retirementCalls, 1);
      expect(coordinator.terminalCleanupAckReady(_callId), isTrue);
      expect(store.read(_callId), isNull);
    },
  );

  test(
    'failed invite retains its handle through nested terminal retirement',
    () async {
      final port = _Port()..failSend = true;
      final store = CallSignalingContextStore();
      var retirementCalls = 0;
      late final CallControlEffectExecutor control;
      final coordinator = CallCoordinator(
        reducer: const CallReducer(),
        cleanupCoordinator: CallCleanupCoordinator(<CallCleanupStep>[
          CallCleanupStep('call_signaling_context', (snapshot) async {
            await control.retireOutgoingPreconnectInvite(snapshot);
            store.purge(snapshot.callId!);
          }, requiredForTerminalAck: true),
        ]),
        historyProjector: CallHistoryProjector(_History()),
        effectExecutor: control = _executor(
          port,
          store,
          cancelOutgoingMailboxInvite:
              ({required recipientDevicePeerId, required callHandle}) async {
                expect(store.read(_callId)?.callHandle, callHandle);
                retirementCalls++;
                return true;
              },
        ),
        clock: () => _now,
        idSource: () => _callId,
      );
      addTearDown(coordinator.dispose);

      await coordinator.placeCall(
        contactPeerId: 'remote-account',
        localAccountPeerId: 'local-account',
        localDeviceId: 'local-device',
      );

      expect(coordinator.lastSnapshot?.isTerminal, isTrue);
      expect(
        coordinator.lastSnapshot?.endReason,
        CallEndReason.signalingFailed,
      );
      expect(retirementCalls, 1);
      expect(coordinator.terminalCleanupAckReady(_callId), isTrue);
      expect(store.read(_callId), isNull);
    },
  );

  test(
    'remote preconnect terminal without a send effect still retires mailbox',
    () async {
      final port = _Port();
      final store = CallSignalingContextStore();
      var retirementCalls = 0;
      late final CallControlEffectExecutor control;
      final coordinator = CallCoordinator(
        reducer: const CallReducer(),
        cleanupCoordinator: CallCleanupCoordinator(<CallCleanupStep>[
          CallCleanupStep('call_signaling_context', (snapshot) async {
            await control.retireOutgoingPreconnectInvite(snapshot);
            store.purge(snapshot.callId!);
          }, requiredForTerminalAck: true),
        ]),
        historyProjector: CallHistoryProjector(_History()),
        effectExecutor: control = _executor(
          port,
          store,
          cancelOutgoingMailboxInvite:
              ({required recipientDevicePeerId, required callHandle}) async {
                retirementCalls++;
                return true;
              },
        ),
        clock: () => _now,
        idSource: () => _callId,
      );
      addTearDown(coordinator.dispose);
      await coordinator.placeCall(
        contactPeerId: 'remote-account',
        localAccountPeerId: 'local-account',
        localDeviceId: 'local-device',
      );

      await coordinator.dispatch(
        CallEvent(
          type: CallEventType.remoteReject,
          eventId: 'remote-decline',
          occurredAt: _now,
          callId: _callId,
          contactPeerId: 'remote-account',
          endReason: CallEndReason.declined,
        ),
      );

      expect(retirementCalls, 1);
      expect(
        port.signals.where(
          (signal) => signal.event == CallSignalType.terminate,
        ),
        isEmpty,
      );
      expect(coordinator.terminalCleanupAckReady(_callId), isTrue);
    },
  );

  test(
    'prepare then invite sends once and returns only mailbox custody receipt',
    () async {
      final port = _Port(
        result: CallControlSendResult(
          directAccepted: true,
          mailboxStored: true,
          directRoute: CallRouteClass.direct,
          mailboxStoreSettled: Future<void>.value(),
        ),
      );
      final store = CallSignalingContextStore();
      final executor = _executor(port, store);

      final ready = await executor.execute(
        const CallEffect(CallEffectType.prepareOutgoingInvite),
        _outgoing(CallState.preparing),
      );
      expect(ready?.type, CallEventType.outgoingInviteReady);
      expect(port.prepareCalls, 1);

      final receipt = await executor.execute(
        const CallEffect(CallEffectType.sendInvite),
        _outgoing(CallState.inviting),
      );
      expect(receipt?.type, CallEventType.mailboxStored);
      expect(receipt?.transportRoute, CallRouteClass.ephemeralMailbox);
      expect(port.signals, hasLength(1));
      expect(port.signals.single.event, CallSignalType.invite);
      expect(port.signals.single.senderSequence, 1);
      expect(port.signals.single.iceGeneration, 0);
      expect(port.signals.single.payload, isEmpty);

      expect(
        await executor.execute(
          const CallEffect(CallEffectType.sendInvite),
          _outgoing(CallState.inviting),
        ),
        isNull,
      );
      expect(port.signals, hasLength(1));
      expect('$executor', isNot(contains('local-account')));
      expect('$executor', isNot(contains('aaaaaaaa-aaaa')));
    },
  );

  test(
    'outgoing native registration sees stored handle before ready and invite',
    () async {
      final port = _Port();
      final store = CallSignalingContextStore();
      final order = <String>[];
      final executor = _executor(
        port,
        store,
        registerOutgoingBeforeInvite: (callId) async {
          order.add('register');
          expect(
            store.read(callId)?.callHandle,
            'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          );
          expect(port.signals, isEmpty);
          return true;
        },
      );

      final ready = await executor.execute(
        const CallEffect(CallEffectType.prepareOutgoingInvite),
        _outgoing(CallState.preparing),
      );
      order.add('ready');
      await executor.execute(
        const CallEffect(CallEffectType.sendInvite),
        _outgoing(CallState.inviting),
      );
      order.add('invite');

      expect(ready?.type, CallEventType.outgoingInviteReady);
      expect(order, <String>['register', 'ready', 'invite']);
      expect(port.signals.single.event, CallSignalType.invite);
    },
  );

  test(
    'outgoing native registration denial or failure purges and fails closed',
    () async {
      final registrars = <Future<bool> Function(CallId)>[
        (_) async => false,
        (_) async => throw StateError('native registration failed'),
      ];

      for (final registerOutgoingBeforeInvite in registrars) {
        final port = _Port();
        final store = CallSignalingContextStore();
        final executor = _executor(
          port,
          store,
          registerOutgoingBeforeInvite: registerOutgoingBeforeInvite,
        );

        final failure = await executor.execute(
          const CallEffect(CallEffectType.prepareOutgoingInvite),
          _outgoing(CallState.preparing),
        );

        expect(failure?.type, CallEventType.negotiationFailed);
        expect(failure?.endReason, CallEndReason.signalingFailed);
        expect(store.read(_callId), isNull);
        expect(port.signals, isEmpty);

        await executor.execute(
          const CallEffect(CallEffectType.sendInvite),
          _outgoing(CallState.inviting),
        );
        expect(port.signals, isEmpty);
      }
    },
  );

  test(
    'default signal expiry reserves five seconds below the hard maximum',
    () async {
      final port = _Port();
      final executor = _executor(port, CallSignalingContextStore());
      await executor.execute(
        const CallEffect(CallEffectType.prepareOutgoingInvite),
        _outgoing(CallState.preparing),
      );

      await executor.execute(
        const CallEffect(CallEffectType.sendInvite),
        _outgoing(CallState.inviting),
      );

      final signalLifetimeMs =
          port.signals.single.expiresAtMs - port.signals.single.createdAtMs;
      expect(
        signalLifetimeMs,
        CallControlEffectExecutor.defaultSignalLifetime.inMilliseconds,
      );
      expect(
        CallSignal.maximumPreconnectLifetimeMs - signalLifetimeMs,
        CallControlEffectExecutor.defaultSignalExpiryHeadroom.inMilliseconds,
      );
    },
  );

  test(
    'direct invite receipt is returned only without mailbox custody',
    () async {
      final port = _Port(
        result: CallControlSendResult(
          directAccepted: true,
          mailboxStored: false,
          directRoute: CallRouteClass.circuitRelay,
          mailboxStoreSettled: Future<void>.value(),
        ),
      );
      final executor = _executor(port, CallSignalingContextStore());
      await executor.execute(
        const CallEffect(CallEffectType.prepareOutgoingInvite),
        _outgoing(CallState.preparing),
      );

      final receipt = await executor.execute(
        const CallEffect(CallEffectType.sendInvite),
        _outgoing(CallState.inviting),
      );

      expect(receipt?.type, CallEventType.directAccepted);
      expect(receipt?.transportRoute, CallRouteClass.circuitRelay);
      expect(receipt?.type, isNot(CallEventType.remoteRinging));
    },
  );

  test(
    'accept sends control only and composite does not start an offer',
    () async {
      final store = CallSignalingContextStore();
      store.captureAuthenticated(
        signal: _authenticatedInvite(_callId),
        callHandle: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      );
      store.markAdmitted(_callId);
      final port = _Port();
      final control = _executor(port, store);
      final negotiation = _RecordingExecutor();
      final composite = CompositeCallEffectExecutor(
        controlExecutor: control,
        negotiationExecutor: negotiation,
      );

      await composite.execute(
        const CallEffect(CallEffectType.prepareAcceptedMedia),
        _incoming(CallState.accepted),
      );
      expect(negotiation.effects, <CallEffectType>[
        CallEffectType.prepareAcceptedMedia,
      ]);

      expect(
        await composite.execute(
          const CallEffect(CallEffectType.sendAccept),
          _incoming(CallState.accepted),
        ),
        isNull,
      );

      expect(port.signals.single.event, CallSignalType.accept);
      expect(negotiation.effects, <CallEffectType>[
        CallEffectType.prepareAcceptedMedia,
      ]);

      await composite.execute(
        const CallEffect(CallEffectType.deliverOffer),
        _incoming(CallState.negotiating),
      );
      expect(negotiation.effects, <CallEffectType>[
        CallEffectType.prepareAcceptedMedia,
        CallEffectType.deliverOffer,
      ]);
    },
  );

  test(
    'reject and terminate carry fixed reasons and purge their contexts',
    () async {
      for (final scenario in <(CallEffectType, CallEndReason, CallSignalType)>[
        (
          CallEffectType.sendReject,
          CallEndReason.declined,
          CallSignalType.reject,
        ),
        (
          CallEffectType.sendTerminate,
          CallEndReason.localHangup,
          CallSignalType.terminate,
        ),
      ]) {
        final store = CallSignalingContextStore();
        store.captureAuthenticated(
          signal: _authenticatedInvite(_callId),
          callHandle: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
        );
        final port = _Port();
        final executor = _executor(port, store);

        await executor.execute(
          CallEffect(scenario.$1),
          _incoming(CallState.ended, endReason: scenario.$2),
        );

        expect(port.signals.single.event, scenario.$3);
        expect(port.signals.single.payload, <String, Object?>{
          'reason': scenario.$2.wireName,
        });
        expect(store.read(_callId), isNull);
      }
    },
  );

  test(
    'busy targets the pending authenticated call, not the active call',
    () async {
      final store = CallSignalingContextStore(maxContexts: 2);
      store.storeOutgoing(
        callId: _callId,
        callHandle: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        localAccountPeerId: 'local-account',
        localDevicePeerId: 'local-device',
        remoteAccountPeerId: 'remote-account',
        remoteDevicePeerId: 'remote-device',
      );
      store.captureAuthenticated(
        signal: _authenticatedInvite(_busyCallId),
        callHandle: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
      );
      final port = _Port();
      final executor = _executor(port, store);

      await executor.execute(
        const CallEffect(CallEffectType.sendBusy),
        _outgoing(CallState.inviting),
      );

      expect(port.signals.single.callId, _busyCallId);
      expect(port.signals.single.event, CallSignalType.reject);
      expect(port.signals.single.payload, <String, Object?>{
        'reason': CallEndReason.busy.wireName,
      });
      expect(store.read(_busyCallId), isNull);
      expect(store.read(_callId), isNotNull);
    },
  );

  test('fixed-shape port failures become redacted signaling failures', () async {
    final port = _Port()..failSend = true;
    final store = CallSignalingContextStore();
    final executor = _executor(port, store);
    await executor.execute(
      const CallEffect(CallEffectType.prepareOutgoingInvite),
      _outgoing(CallState.preparing),
    );

    final failure = await executor.execute(
      const CallEffect(CallEffectType.sendInvite),
      _outgoing(CallState.inviting),
    );

    expect(failure?.type, CallEventType.negotiationFailed);
    expect(failure?.endReason, CallEndReason.signalingFailed);
    expect(
      '${const CallControlSignalingPortException(CallControlSignalingPortErrorCode.transportUnavailable)}',
      'CallControlSignalingPortException(transportUnavailable)',
    );
    expect('$executor', isNot(contains('transport secret')));
  });
}

CallControlEffectExecutor _executor(
  _Port port,
  CallSignalingContextStore store, {
  Future<bool> Function(CallId callId)? registerOutgoingBeforeInvite,
  OutgoingMailboxInviteCanceller? cancelOutgoingMailboxInvite,
}) => CallControlEffectExecutor(
  contextStore: store,
  signalingPort: port,
  clock: () => _now,
  idSource: _MessageIds().next,
  registerOutgoingBeforeInvite: registerOutgoingBeforeInvite,
  cancelOutgoingMailboxInvite: cancelOutgoingMailboxInvite,
);

final class _MessageIds {
  static const _ids = <String>[
    '99999999-9999-4999-8999-999999999999',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
  ];
  int _next = 0;

  CallId next() => CallId.parse(_ids[_next++ % _ids.length]);
}

final class _Port implements CallControlSignalingPort {
  _Port({CallControlSendResult? result, this.onSend, this.failSignalType})
    : result =
          result ??
          CallControlSendResult(
            directAccepted: true,
            mailboxStored: false,
            directRoute: CallRouteClass.direct,
            mailboxStoreSettled: Future<void>.value(),
          );

  final CallControlSendResult result;
  final Future<CallControlSendResult> Function(
    CallSignal signal,
    String callHandle,
  )?
  onSend;
  final CallSignalType? failSignalType;
  final List<CallSignal> signals = <CallSignal>[];
  final List<String> callHandles = <String>[];
  int prepareCalls = 0;
  bool failSend = false;

  @override
  Future<OutgoingCallSignalingPreparation> prepareOutgoingInvite(
    CallSessionSnapshot snapshot,
  ) async {
    prepareCalls++;
    return const OutgoingCallSignalingPreparation(
      callHandle: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      remoteAccountPeerId: 'remote-account',
      remoteDevicePeerId: 'remote-device',
    );
  }

  @override
  Future<CallControlSendResult> send({
    required CallSignal signal,
    required String callHandle,
  }) async {
    signals.add(signal);
    callHandles.add(callHandle);
    if (failSend || signal.event == failSignalType) {
      throw const CallControlSignalingPortException(
        CallControlSignalingPortErrorCode.transportUnavailable,
      );
    }
    final send = onSend;
    if (send != null) return send(signal, callHandle);
    return result;
  }
}

final class _RecordingExecutor implements CallEffectExecutor {
  final List<CallEffectType> effects = <CallEffectType>[];

  @override
  Future<CallEvent?> execute(
    CallEffect effect,
    CallSessionSnapshot snapshot,
  ) async {
    effects.add(effect.type);
    return null;
  }
}

final class _History implements CallHistoryRepository {
  @override
  Future<CallHistoryEntry?> getByCallId(CallId callId) async => null;

  @override
  Future<List<CallHistoryEntry>> listForContact(String peerId) async =>
      const <CallHistoryEntry>[];

  @override
  Future<void> upsertTerminal(CallHistoryEntry entry) async {}
}
