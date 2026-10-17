import 'package:flutter_app/features/call/domain/call_end_reason.dart';
import 'package:flutter_app/features/call/domain/call_event.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_test/flutter_test.dart';

final _callA = CallId.parse('11111111-1111-4111-8111-111111111111');
final _t0 = DateTime.utc(2026, 8, 30, 12);

CallEvent _event(
  CallEventType type, {
  String? eventId,
  DateTime? at,
  DateTime? expiresAt,
  IncomingCallAdmission admission = IncomingCallAdmission.accepted,
  CallTimeoutKind? timeoutKind,
  CallNativeAction? nativeAction,
  CallEndReason? endReason,
  String? candidateId,
  int? pathEpoch,
  int? reconnectGeneration,
}) => CallEvent(
  type: type,
  eventId: eventId ?? '${type.name}-event',
  occurredAt: at ?? _t0,
  callId: _callA,
  contactPeerId: 'contact-account-a',
  localAccountPeerId: 'local-account',
  localDeviceId: 'local-device',
  remoteAccountPeerId: 'contact-account-a',
  remoteDeviceId: 'contact-device-a',
  expiresAt: expiresAt,
  admission: admission,
  timeoutKind: timeoutKind,
  nativeAction: nativeAction,
  endReason: endReason,
  candidateId: candidateId,
  pathEpoch: pathEpoch,
  reconnectGeneration: reconnectGeneration,
);

CallSessionSnapshot _reduce(List<CallEvent> events) {
  const reducer = CallReducer();
  var snapshot = CallSessionSnapshot.idle(now: _t0);
  for (final event in events) {
    snapshot = reducer.reduce(snapshot, event).snapshot;
  }
  return snapshot;
}

void main() {
  for (final direction in CallDirection.values) {
    test(
      'audio interruption upgrades once to transport recovery for ${direction.name}',
      () {
        const reducer = CallReducer();
        final connected = CallSessionSnapshot.active(
          callId: _callA,
          contactPeerId: 'contact',
          direction: direction,
          state: CallState.connected,
          callerAccountPeerId: 'local',
          callerDeviceId: 'device',
          startedAt: _t0,
          acceptedAt: _t0,
          connectedAt: _t0,
        );
        final interrupted = reducer.reduce(
          connected,
          _event(CallEventType.audioInterrupted),
        );
        expect(interrupted.snapshot.state, CallState.reconnecting);
        expect(interrupted.snapshot.transportRecoveryRequired, isFalse);
        expect(interrupted.effects.map((e) => e.type), [
          CallEffectType.scheduleReconnectTimeout,
        ]);
        final lost = reducer.reduce(
          interrupted.snapshot,
          _event(CallEventType.mediaLost),
        );
        expect(
          lost.snapshot.reconnectGeneration,
          interrupted.snapshot.reconnectGeneration,
        );
        expect(lost.snapshot.transportRecoveryRequired, isTrue);
        expect(lost.effects.map((e) => e.type), [
          direction == CallDirection.outgoing
              ? CallEffectType.restartIce
              : CallEffectType.requestIceRestart,
        ]);
        final repeated = reducer.reduce(
          lost.snapshot,
          _event(CallEventType.mediaLost, eventId: 'repeat'),
        );
        expect(repeated.effects, isEmpty);
        final expired = reducer.reduce(
          lost.snapshot,
          _event(CallEventType.timeout, timeoutKind: CallTimeoutKind.reconnect),
        );
        expect(expired.snapshot.endReason, CallEndReason.reconnectFailed);
      },
    );
  }

  group('VC2-02 pure reducer causal matrix', () {
    final cases =
        <
          ({
            String name,
            List<CallEvent> events,
            CallState state,
            CallEndReason? reason,
          })
        >[
          (
            name: '01 outgoing place invite ringing accept',
            events: <CallEvent>[
              _event(CallEventType.place),
              _event(CallEventType.outgoingInviteReady),
              _event(CallEventType.remoteRinging),
              _event(CallEventType.remoteAccept),
            ],
            state: CallState.accepted,
            reason: null,
          ),
          (
            name: '02 incoming validate present ring answer',
            events: <CallEvent>[
              _event(CallEventType.remoteInvite),
              _event(CallEventType.incomingValidated),
              _event(CallEventType.systemUiPresented),
              _event(CallEventType.answer),
            ],
            state: CallState.accepted,
            reason: null,
          ),
          (
            name: '03 direct ack does not imply ringing',
            events: <CallEvent>[
              _event(CallEventType.place),
              _event(CallEventType.outgoingInviteReady),
              _event(CallEventType.directAccepted),
            ],
            state: CallState.inviting,
            reason: null,
          ),
          (
            name: '04 mailbox store does not imply ringing',
            events: <CallEvent>[
              _event(CallEventType.place),
              _event(CallEventType.outgoingInviteReady),
              _event(CallEventType.mailboxStored),
            ],
            state: CallState.inviting,
            reason: null,
          ),
          (
            name: '05 decline before accept is terminal',
            events: <CallEvent>[
              _event(CallEventType.remoteInvite),
              _event(CallEventType.incomingValidated),
              _event(CallEventType.systemUiPresented),
              _event(CallEventType.decline),
            ],
            state: CallState.ended,
            reason: CallEndReason.declined,
          ),
          (
            name: '06 caller cancel wins recipient accept race',
            events: <CallEvent>[
              _event(CallEventType.place),
              _event(CallEventType.outgoingInviteReady),
              _event(CallEventType.cancel),
              _event(CallEventType.remoteAccept),
            ],
            state: CallState.ended,
            reason: CallEndReason.callerCancelled,
          ),
          (
            name: '07 no answer timeout is terminal',
            events: <CallEvent>[
              _event(CallEventType.place),
              _event(CallEventType.outgoingInviteReady),
              _event(
                CallEventType.timeout,
                timeoutKind: CallTimeoutKind.noAnswer,
              ),
            ],
            state: CallState.ended,
            reason: CallEndReason.noAnswer,
          ),
          (
            name: '08 invite mailbox expiry is terminal',
            events: <CallEvent>[
              _event(CallEventType.place),
              _event(CallEventType.outgoingInviteReady),
              _event(CallEventType.mailboxExpired),
            ],
            state: CallState.ended,
            reason: CallEndReason.expired,
          ),
          (
            name: '09 duplicate direct and mailbox invite has one session',
            events: <CallEvent>[
              _event(CallEventType.remoteInvite, eventId: 'direct-invite'),
              _event(CallEventType.remoteInvite, eventId: 'mailbox-invite'),
            ],
            state: CallState.incomingValidating,
            reason: null,
          ),
          (
            name: '10 duplicate push presentation does not ring twice',
            events: <CallEvent>[
              _event(CallEventType.remoteInvite),
              _event(CallEventType.incomingValidated),
              _event(
                CallEventType.systemUiPresented,
                eventId: 'push-presented',
              ),
              _event(
                CallEventType.systemUiPresented,
                eventId: 'mailbox-presented',
              ),
            ],
            state: CallState.ringing,
            reason: null,
          ),
          (
            name: '11 duplicate terminate stays terminal',
            events: <CallEvent>[
              _event(CallEventType.remoteInvite),
              _event(
                CallEventType.remoteTerminate,
                eventId: 'terminate-direct',
              ),
              _event(
                CallEventType.remoteTerminate,
                eventId: 'terminate-mailbox',
              ),
            ],
            state: CallState.ended,
            reason: CallEndReason.remoteHangup,
          ),
          (
            name: '12 out of order remote answer is rejected',
            events: <CallEvent>[
              _event(CallEventType.place),
              _event(CallEventType.outgoingInviteReady),
              _event(CallEventType.remoteAnswer),
            ],
            state: CallState.inviting,
            reason: null,
          ),
          (
            name: '13 late offer after terminal is ignored',
            events: <CallEvent>[
              _event(CallEventType.place),
              _event(CallEventType.cancel),
              _event(CallEventType.remoteOffer),
            ],
            state: CallState.ended,
            reason: CallEndReason.callerCancelled,
          ),
          (
            name: '14 late candidate after terminal is ignored',
            events: <CallEvent>[
              _event(CallEventType.place),
              _event(CallEventType.cancel),
              _event(CallEventType.remoteIce, candidateId: 'late-candidate'),
            ],
            state: CallState.ended,
            reason: CallEndReason.callerCancelled,
          ),
          (
            name: '15 blocked invite cannot create a session',
            events: <CallEvent>[
              _event(
                CallEventType.remoteInvite,
                admission: IncomingCallAdmission.blocked,
              ),
            ],
            state: CallState.idle,
            reason: null,
          ),
          (
            name: '16 unknown invite cannot create a session',
            events: <CallEvent>[
              _event(
                CallEventType.remoteInvite,
                admission: IncomingCallAdmission.unknownContact,
              ),
            ],
            state: CallState.idle,
            reason: null,
          ),
          (
            name: '17 wrong device invite cannot create a session',
            events: <CallEvent>[
              _event(
                CallEventType.remoteInvite,
                admission: IncomingCallAdmission.wrongDevice,
              ),
            ],
            state: CallState.idle,
            reason: null,
          ),
          (
            name: '18 unsupported version cannot create a session',
            events: <CallEvent>[
              _event(
                CallEventType.remoteInvite,
                admission: IncomingCallAdmission.unsupportedVersion,
              ),
            ],
            state: CallState.idle,
            reason: null,
          ),
          (
            name: '19 invalid signature cannot create a session',
            events: <CallEvent>[
              _event(
                CallEventType.remoteInvite,
                admission: IncomingCallAdmission.invalidSignature,
              ),
            ],
            state: CallState.idle,
            reason: null,
          ),
          (
            name: '20 malformed envelope cannot create a session',
            events: <CallEvent>[
              _event(
                CallEventType.remoteInvite,
                admission: IncomingCallAdmission.malformed,
              ),
            ],
            state: CallState.idle,
            reason: null,
          ),
          (
            name: '21 shutdown while preparing is terminal',
            events: <CallEvent>[
              _event(CallEventType.place),
              _event(CallEventType.appShutdown),
            ],
            state: CallState.ended,
            reason: CallEndReason.appShutdown,
          ),
          (
            name: '22 shutdown while inviting is terminal',
            events: <CallEvent>[
              _event(CallEventType.place),
              _event(CallEventType.outgoingInviteReady),
              _event(CallEventType.appShutdown),
            ],
            state: CallState.ended,
            reason: CallEndReason.appShutdown,
          ),
          (
            name: '23 shutdown while incoming-validating is terminal',
            events: <CallEvent>[
              _event(CallEventType.remoteInvite),
              _event(CallEventType.appShutdown),
            ],
            state: CallState.ended,
            reason: CallEndReason.appShutdown,
          ),
          (
            name: '24 shutdown while ringing is terminal',
            events: <CallEvent>[
              _event(CallEventType.remoteInvite),
              _event(CallEventType.incomingValidated),
              _event(CallEventType.systemUiPresented),
              _event(CallEventType.appShutdown),
            ],
            state: CallState.ended,
            reason: CallEndReason.appShutdown,
          ),
          (
            name: '25 shutdown while accepted is terminal',
            events: <CallEvent>[
              _event(CallEventType.place),
              _event(CallEventType.outgoingInviteReady),
              _event(CallEventType.remoteAccept),
              _event(CallEventType.appShutdown),
            ],
            state: CallState.ended,
            reason: CallEndReason.appShutdown,
          ),
          (
            name: '26 negotiation and simulated media connect',
            events: <CallEvent>[
              _event(CallEventType.place),
              _event(CallEventType.outgoingInviteReady),
              _event(CallEventType.remoteAccept),
              _event(CallEventType.negotiationReady),
              _event(CallEventType.mediaConnected),
            ],
            state: CallState.connected,
            reason: null,
          ),
          (
            name: '27 simulated media loss and recovery',
            events: <CallEvent>[
              _event(CallEventType.place),
              _event(CallEventType.outgoingInviteReady),
              _event(CallEventType.remoteAccept),
              _event(CallEventType.negotiationReady),
              _event(CallEventType.mediaConnected),
              _event(CallEventType.mediaLost),
              _event(CallEventType.mediaRecovered),
            ],
            state: CallState.connected,
            reason: null,
          ),
        ];

    for (final testCase in cases) {
      test(testCase.name, () {
        final snapshot = _reduce(testCase.events);
        expect(snapshot.state, testCase.state);
        expect(snapshot.endReason, testCase.reason);
      });
    }

    test('expired incoming invite records history without presenting UI', () {
      const reducer = CallReducer();
      final reduction = reducer.reduce(
        CallSessionSnapshot.idle(now: _t0),
        _event(
          CallEventType.remoteInvite,
          at: _t0,
          expiresAt: _t0.subtract(const Duration(milliseconds: 1)),
        ),
      );

      expect(reduction.snapshot.state, CallState.ended);
      expect(reduction.snapshot.endReason, CallEndReason.expired);
      expect(
        reduction.effects.map((effect) => effect.type),
        contains(CallEffectType.projectHistory),
      );
      expect(
        reduction.effects.map((effect) => effect.type),
        isNot(contains(CallEffectType.presentIncomingCall)),
      );
    });

    test('candidate and accepted-event ledgers are bounded', () {
      const reducer = CallReducer(
        policy: CallReducerPolicy(
          recentEventCapacity: 3,
          candidateQueueCapacity: 2,
          effectQueueCapacity: 8,
        ),
      );
      var snapshot = CallSessionSnapshot.idle(now: _t0);
      for (final event in <CallEvent>[
        _event(CallEventType.place, eventId: 'place'),
        _event(CallEventType.outgoingInviteReady, eventId: 'invite-ready'),
        _event(CallEventType.remoteAccept, eventId: 'accepted'),
        _event(
          CallEventType.remoteIce,
          eventId: 'candidate-event-1',
          candidateId: 'candidate-1',
        ),
        _event(
          CallEventType.remoteIce,
          eventId: 'candidate-event-2',
          candidateId: 'candidate-2',
        ),
      ]) {
        snapshot = reducer.reduce(snapshot, event).snapshot;
      }
      final overflow = reducer.reduce(
        snapshot,
        _event(
          CallEventType.remoteIce,
          eventId: 'candidate-event-3',
          candidateId: 'candidate-3',
        ),
      );

      expect(snapshot.recentEventIds, hasLength(3));
      expect(snapshot.pendingCandidateIds, hasLength(2));
      expect(overflow.decision, CallEventDecision.rejected);
      expect(overflow.reason, CallReductionReason.candidateQueueFull);
      expect(overflow.snapshot.pendingCandidateIds, hasLength(2));
    });

    test(
      'candidate completion releases capacity and preserves deduplication',
      () {
        const reducer = CallReducer(
          policy: CallReducerPolicy(
            recentEventCapacity: 3,
            candidateQueueCapacity: 2,
          ),
        );
        var snapshot = _reduce(<CallEvent>[
          _event(CallEventType.place),
          _event(CallEventType.outgoingInviteReady),
          _event(CallEventType.remoteAccept),
        ]);

        CallReduction dispatch(CallEventType type, String eventId, String id) {
          final result = reducer.reduce(
            snapshot,
            _event(type, eventId: eventId, candidateId: id),
          );
          snapshot = result.snapshot;
          return result;
        }

        dispatch(CallEventType.remoteIce, 'pending-event', 'pending');
        for (var index = 0; index < 70; index++) {
          final id = 'candidate-$index';
          expect(
            dispatch(CallEventType.remoteIce, 'ice-$index', id).decision,
            CallEventDecision.applied,
          );
          expect(snapshot.pendingCandidateIds, <String>['pending', id]);
          expect(
            dispatch(
              CallEventType.iceCandidateHandled,
              'done-$index',
              id,
            ).decision,
            CallEventDecision.applied,
          );
          expect(snapshot.pendingCandidateIds, <String>['pending']);
        }
        expect(snapshot.recentCandidateIds, <String>[
          'candidate-67',
          'candidate-68',
          'candidate-69',
        ]);
        expect(
          dispatch(
            CallEventType.remoteIce,
            'new-event-same-id',
            'candidate-69',
          ).reason,
          CallReductionReason.duplicateEvent,
        );
        // The original event has left the replay window, but its candidate is
        // still in flight and cannot be admitted a second time.
        expect(snapshot.recentEventIds, isNot(contains('pending-event')));
        expect(
          dispatch(CallEventType.remoteIce, 'pending-replay', 'pending').reason,
          CallReductionReason.duplicateEvent,
        );
        dispatch(CallEventType.remoteIce, 'fills-capacity', 'another-pending');
        expect(
          dispatch(
            CallEventType.remoteIce,
            'overflow-event',
            'overflow',
          ).reason,
          CallReductionReason.candidateQueueFull,
        );
        expect(snapshot.pendingCandidateIds, <String>[
          'pending',
          'another-pending',
        ]);
      },
    );

    test('terminal reduction requests cleanup once and terminal dominates', () {
      const reducer = CallReducer();
      var snapshot = _reduce(<CallEvent>[
        _event(CallEventType.place),
        _event(CallEventType.outgoingInviteReady),
      ]);
      final terminal = reducer.reduce(snapshot, _event(CallEventType.cancel));
      snapshot = terminal.snapshot;
      final late = reducer.reduce(
        snapshot,
        _event(CallEventType.remoteAccept, eventId: 'late-accept'),
      );

      expect(terminal.terminalCleanupRequired, isTrue);
      expect(late.terminalCleanupRequired, isFalse);
      expect(late.decision, CallEventDecision.ignored);
      expect(late.reason, CallReductionReason.terminalDominates);
    });

    test('native decline and end signal the peer before terminal cleanup', () {
      const reducer = CallReducer();
      for (final scenario
          in <
            ({
              CallNativeAction action,
              CallEffectType signal,
              CallEndReason reason,
            })
          >[
            (
              action: CallNativeAction.decline,
              signal: CallEffectType.sendReject,
              reason: CallEndReason.declined,
            ),
            (
              action: CallNativeAction.end,
              signal: CallEffectType.sendTerminate,
              reason: CallEndReason.localHangup,
            ),
          ]) {
        final beforeNativeAction = _reduce(<CallEvent>[
          _event(CallEventType.remoteInvite),
          _event(CallEventType.incomingValidated),
          _event(CallEventType.systemUiPresented),
          if (scenario.action == CallNativeAction.end) ...<CallEvent>[
            _event(CallEventType.answer),
            _event(CallEventType.remoteOffer),
            _event(CallEventType.mediaConnected),
          ],
        ]);
        final reduction = reducer.reduce(
          beforeNativeAction,
          _event(
            CallEventType.nativeAction,
            eventId: 'native-${scenario.action.name}',
            nativeAction: scenario.action,
          ),
        );

        expect(reduction.decision, CallEventDecision.applied);
        expect(reduction.snapshot.endReason, scenario.reason);
        expect(reduction.effects.map((effect) => effect.type), <CallEffectType>[
          CallEffectType.cancelTimers,
          scenario.signal,
          CallEffectType.cleanup,
          CallEffectType.projectHistory,
        ]);
      }
    });

    test('native end preserves the platform-classified terminal reason', () {
      const reducer = CallReducer();
      final ringing = _reduce(<CallEvent>[
        _event(CallEventType.remoteInvite),
        _event(CallEventType.incomingValidated),
        _event(CallEventType.systemUiPresented),
      ]);

      final reduction = reducer.reduce(
        ringing,
        _event(
          CallEventType.nativeAction,
          eventId: 'native-expired',
          nativeAction: CallNativeAction.end,
          endReason: CallEndReason.expired,
        ),
      );

      expect(reduction.decision, CallEventDecision.applied);
      expect(reduction.snapshot.endReason, CallEndReason.expired);
      expect(reduction.effects.map((effect) => effect.type), <CallEffectType>[
        CallEffectType.cancelTimers,
        CallEffectType.sendTerminate,
        CallEffectType.cleanup,
        CallEffectType.projectHistory,
      ]);
    });

    test('out-of-order answer before accept is explicitly rejected', () {
      const reducer = CallReducer();
      final inviting = _reduce(<CallEvent>[
        _event(CallEventType.place),
        _event(CallEventType.outgoingInviteReady),
      ]);

      final reduction = reducer.reduce(
        inviting,
        _event(CallEventType.remoteAnswer),
      );

      expect(reduction.decision, CallEventDecision.rejected);
      expect(reduction.reason, CallReductionReason.stateMismatch);
      expect(reduction.snapshot.state, CallState.inviting);
    });

    test(
      'a dispatched wake confirms custody without inventing remote alerting',
      () {
        const reducer = CallReducer();
        final inviting = _reduce(<CallEvent>[
          _event(CallEventType.place),
          _event(CallEventType.outgoingInviteReady),
        ]);

        final alerted = reducer.reduce(
          inviting,
          _event(CallEventType.wakeRequested),
        );
        expect(alerted.decision, CallEventDecision.applied);
        expect(alerted.snapshot.state, CallState.inviting);
        expect(alerted.snapshot.ringingAt, isNull);
        expect(
          alerted.snapshot.mailboxCustodyConfirmed,
          isTrue,
          reason: 'a dispatched wake implies the invite is in the mailbox',
        );

        final rung = reducer.reduce(
          alerted.snapshot,
          _event(CallEventType.remoteRinging),
        );
        expect(rung.decision, CallEventDecision.applied);
        expect(rung.snapshot.state, CallState.ringing);

        final accepted = reducer.reduce(
          alerted.snapshot,
          _event(CallEventType.remoteAccept),
        );
        expect(accepted.snapshot.state, CallState.accepted);
      },
    );

    test('a wake receipt outside inviting changes no state', () {
      const reducer = CallReducer();
      final ringing = _reduce(<CallEvent>[
        _event(CallEventType.place),
        _event(CallEventType.outgoingInviteReady),
        _event(CallEventType.remoteRinging),
      ]);

      final receipt = reducer.reduce(
        ringing,
        _event(CallEventType.wakeRequested),
      );
      expect(receipt.snapshot.state, CallState.ringing);
      expect(receipt.snapshot.ringingAt, ringing.ringingAt);
    });

    test('late offer and candidate after terminal are explicitly ignored', () {
      const reducer = CallReducer();
      final terminal = reducer
          .reduce(
            _reduce(<CallEvent>[_event(CallEventType.place)]),
            _event(CallEventType.cancel),
          )
          .snapshot;

      for (final event in <CallEvent>[
        _event(CallEventType.remoteOffer, eventId: 'late-offer'),
        _event(
          CallEventType.remoteIce,
          eventId: 'late-candidate-event',
          candidateId: 'late-candidate',
        ),
      ]) {
        final reduction = reducer.reduce(terminal, event);
        expect(reduction.decision, CallEventDecision.ignored);
        expect(reduction.reason, CallReductionReason.terminalDominates);
        expect(reduction.snapshot, same(terminal));
      }
    });

    test('effect queue bound rejects a transition before state mutation', () {
      const reducer = CallReducer(
        policy: CallReducerPolicy(
          recentEventCapacity: 8,
          candidateQueueCapacity: 8,
          effectQueueCapacity: 1,
        ),
      );
      final preparing = reducer
          .reduce(
            CallSessionSnapshot.idle(now: _t0),
            _event(CallEventType.place),
          )
          .snapshot;

      final overflow = reducer.reduce(
        preparing,
        _event(CallEventType.outgoingInviteReady),
      );

      expect(overflow.decision, CallEventDecision.rejected);
      expect(overflow.reason, CallReductionReason.effectQueueFull);
      expect(overflow.snapshot.state, CallState.preparing);
    });

    test(
      'shutdown terminates every active non-terminal state with one cleanup effect',
      () {
        const reducer = CallReducer();
        for (final state in <CallState>[
          CallState.preparing,
          CallState.inviting,
          CallState.incomingValidating,
          CallState.ringing,
          CallState.accepted,
          CallState.negotiating,
          CallState.connected,
          CallState.reconnecting,
          CallState.ending,
        ]) {
          final snapshot = CallSessionSnapshot.active(
            callId: _callA,
            contactPeerId: 'contact-account-a',
            direction: CallDirection.outgoing,
            state: state,
            callerAccountPeerId: 'local-account',
            callerDeviceId: 'local-device',
            startedAt: _t0,
          );
          final reduction = reducer.reduce(
            snapshot,
            _event(
              CallEventType.appShutdown,
              eventId: 'shutdown-${state.name}',
            ),
          );
          expect(reduction.snapshot.state, CallState.ended, reason: state.name);
          expect(
            reduction.snapshot.endReason,
            CallEndReason.appShutdown,
            reason: state.name,
          );
          expect(reduction.terminalCleanupRequired, isTrue, reason: state.name);
          expect(
            reduction.effects.where(
              (effect) => effect.type == CallEffectType.cleanup,
            ),
            hasLength(1),
            reason: state.name,
          );
        }
      },
    );

    test('terminate wins answer ringing and presentation races', () {
      const reducer = CallReducer();
      for (final lateType in <CallEventType>[
        CallEventType.answer,
        CallEventType.remoteAccept,
        CallEventType.remoteRinging,
        CallEventType.systemUiPresented,
      ]) {
        var snapshot = _reduce(<CallEvent>[_event(CallEventType.remoteInvite)]);
        snapshot = reducer
            .reduce(
              snapshot,
              _event(
                CallEventType.remoteTerminate,
                eventId: 'terminate-${lateType.name}',
              ),
            )
            .snapshot;
        final late = reducer.reduce(
          snapshot,
          _event(lateType, eventId: 'late-${lateType.name}'),
        );
        expect(late.snapshot.state, CallState.ended, reason: lateType.name);
        expect(
          late.snapshot.endReason,
          CallEndReason.remoteHangup,
          reason: lateType.name,
        );
        expect(late.reason, CallReductionReason.terminalDominates);
      }
    });

    test('native presentation cannot ring before validation proof', () {
      const reducer = CallReducer();
      final validating = reducer
          .reduce(
            CallSessionSnapshot.idle(now: _t0),
            _event(CallEventType.remoteInvite),
          )
          .snapshot;
      final premature = reducer.reduce(
        validating,
        _event(CallEventType.systemUiPresented),
      );

      expect(premature.decision, CallEventDecision.rejected);
      expect(premature.snapshot.state, CallState.incomingValidating);
      expect(premature.snapshot.incomingValidated, isFalse);
    });

    test('direct failure cannot beat committed mailbox custody', () {
      const reducer = CallReducer();
      var snapshot = _reduce(<CallEvent>[
        _event(CallEventType.place),
        _event(CallEventType.outgoingInviteReady),
      ]);
      snapshot = reducer
          .reduce(snapshot, _event(CallEventType.mailboxStored))
          .snapshot;
      final directFailure = reducer.reduce(
        snapshot,
        _event(CallEventType.directFailed),
      );

      expect(directFailure.snapshot.state, CallState.inviting);
      expect(directFailure.snapshot.mailboxCustodyConfirmed, isTrue);
      expect(directFailure.terminalCleanupRequired, isFalse);
    });

    test('late preconnect timers cannot end accepted or media states', () {
      const reducer = CallReducer();
      final accepted = _reduce(<CallEvent>[
        _event(CallEventType.place),
        _event(CallEventType.outgoingInviteReady),
        _event(CallEventType.remoteAccept),
      ]);
      final negotiating = reducer
          .reduce(accepted, _event(CallEventType.negotiationReady))
          .snapshot;
      final connected = reducer
          .reduce(negotiating, _event(CallEventType.mediaConnected))
          .snapshot;
      for (final snapshot in <CallSessionSnapshot>[
        accepted,
        negotiating,
        connected,
      ]) {
        for (final event in <CallEvent>[
          _event(
            CallEventType.timeout,
            eventId: 'stale-no-answer-${snapshot.state.name}',
            timeoutKind: CallTimeoutKind.noAnswer,
          ),
          _event(
            CallEventType.timeout,
            eventId: 'stale-expiry-${snapshot.state.name}',
            timeoutKind: CallTimeoutKind.inviteExpiry,
          ),
          _event(
            CallEventType.mailboxExpired,
            eventId: 'stale-mailbox-${snapshot.state.name}',
          ),
        ]) {
          final reduction = reducer.reduce(snapshot, event);
          expect(reduction.snapshot.state, snapshot.state);
          expect(reduction.terminalCleanupRequired, isFalse);
        }
      }
    });

    test('ICE is rejected before acceptance and queued after acceptance', () {
      const reducer = CallReducer();
      final inviting = _reduce(<CallEvent>[
        _event(CallEventType.place),
        _event(CallEventType.outgoingInviteReady),
      ]);
      final early = reducer.reduce(
        inviting,
        _event(CallEventType.remoteIce, candidateId: 'candidate-early'),
      );
      final accepted = reducer
          .reduce(inviting, _event(CallEventType.remoteAccept))
          .snapshot;
      final acceptedCandidate = reducer.reduce(
        accepted,
        _event(
          CallEventType.remoteIce,
          eventId: 'accepted-candidate',
          candidateId: 'candidate-accepted',
        ),
      );

      expect(early.decision, CallEventDecision.rejected);
      expect(early.snapshot.pendingCandidateIds, isEmpty);
      expect(acceptedCandidate.snapshot.pendingCandidateIds, <String>[
        'candidate-accepted',
      ]);
    });

    test('terminal transition obeys effect bound without staying active', () {
      const reducer = CallReducer(
        policy: CallReducerPolicy(
          recentEventCapacity: 8,
          candidateQueueCapacity: 8,
          effectQueueCapacity: 1,
        ),
      );
      final preparing = reducer
          .reduce(
            CallSessionSnapshot.idle(now: _t0),
            _event(CallEventType.place),
          )
          .snapshot;
      final terminal = reducer.reduce(preparing, _event(CallEventType.cancel));

      expect(terminal.snapshot.state, CallState.ended);
      expect(terminal.effects.length, lessThanOrEqualTo(1));
      expect(terminal.terminalCleanupRequired, isTrue);
    });

    test('outgoing remote accept starts negotiation in the same reduction', () {
      const reducer = CallReducer();
      final inviting = _reduce(<CallEvent>[
        _event(CallEventType.place),
        _event(CallEventType.outgoingInviteReady),
      ]);

      final accepted = reducer.reduce(
        inviting,
        _event(CallEventType.remoteAccept),
      );

      expect(accepted.snapshot.state, CallState.accepted);
      expect(accepted.effects.map((effect) => effect.type), <CallEffectType>[
        CallEffectType.cancelTimers,
        CallEffectType.scheduleNegotiationTimeout,
        CallEffectType.startNegotiation,
      ]);
    });

    test('incoming answer prepares media before accept signaling', () {
      const reducer = CallReducer();
      final ringing = _reduce(<CallEvent>[
        _event(CallEventType.remoteInvite),
        _event(CallEventType.incomingValidated),
        _event(CallEventType.systemUiPresented),
      ]);

      final accepted = reducer.reduce(ringing, _event(CallEventType.answer));

      expect(accepted.snapshot.state, CallState.accepted);
      expect(accepted.effects.map((effect) => effect.type), <CallEffectType>[
        CallEffectType.cancelTimers,
        CallEffectType.scheduleNegotiationTimeout,
        CallEffectType.prepareAcceptedMedia,
        CallEffectType.sendAccept,
      ]);
    });

    test('maximum-skew invite keeps connected and terminal time monotonic', () {
      const reducer = CallReducer();
      final inviteAt = _t0.add(const Duration(seconds: 30));
      var snapshot = CallSessionSnapshot.idle(now: _t0);

      for (final event in <CallEvent>[
        _event(CallEventType.remoteInvite, at: inviteAt),
        _event(CallEventType.incomingValidated, at: _t0),
        _event(CallEventType.systemUiPresented, at: _t0),
        _event(CallEventType.answer, at: _t0),
        _event(CallEventType.negotiationReady, at: _t0),
        _event(CallEventType.mediaConnected, at: _t0),
      ]) {
        snapshot = reducer.reduce(snapshot, event).snapshot;
      }

      expect(snapshot.state, CallState.connected);
      expect(snapshot.startedAt, inviteAt);
      expect(snapshot.ringingAt, inviteAt);
      expect(snapshot.acceptedAt, inviteAt);
      expect(snapshot.connectedAt, inviteAt);
      expect(snapshot.observedAt, inviteAt);

      final terminal = reducer
          .reduce(snapshot, _event(CallEventType.appShutdown, at: _t0))
          .snapshot;
      expect(terminal.state, CallState.ended);
      expect(terminal.endedAt, inviteAt);
      expect(terminal.observedAt, inviteAt);
    });

    test('negotiation failure notifies the peer before shared cleanup', () {
      const reducer = CallReducer();
      final accepted = _reduce(<CallEvent>[
        _event(CallEventType.place),
        _event(CallEventType.outgoingInviteReady),
        _event(CallEventType.remoteAccept),
      ]);

      final failed = reducer.reduce(
        accepted,
        _event(CallEventType.negotiationFailed),
      );

      expect(failed.snapshot.state, CallState.ended);
      expect(failed.effects.map((effect) => effect.type), <CallEffectType>[
        CallEffectType.cancelTimers,
        CallEffectType.sendTerminate,
        CallEffectType.cleanup,
        CallEffectType.projectHistory,
      ]);
    });

    test(
      'initial negotiation timeout ends accepted and negotiating states',
      () {
        const reducer = CallReducer();
        for (final state in <CallState>[
          CallState.accepted,
          CallState.negotiating,
        ]) {
          final snapshot = CallSessionSnapshot.active(
            callId: _callA,
            contactPeerId: 'contact-account-a',
            direction: CallDirection.outgoing,
            state: state,
            callerAccountPeerId: 'local-account',
            callerDeviceId: 'local-device',
            startedAt: _t0,
            acceptedAt: _t0,
          );
          final timedOut = reducer.reduce(
            snapshot,
            _event(
              CallEventType.timeout,
              eventId: 'negotiation-timeout-${state.name}',
              timeoutKind: CallTimeoutKind.negotiation,
            ),
          );
          expect(timedOut.snapshot.state, CallState.ended);
          expect(timedOut.snapshot.endReason, CallEndReason.mediaFailed);
        }
      },
    );

    test('media loss starts one bounded reconnect attempt', () {
      const reducer = CallReducer();
      final connected = CallSessionSnapshot.active(
        callId: _callA,
        contactPeerId: 'contact-account-a',
        direction: CallDirection.outgoing,
        state: CallState.connected,
        callerAccountPeerId: 'local-account',
        callerDeviceId: 'local-device',
        startedAt: _t0,
        acceptedAt: _t0,
        connectedAt: _t0,
      );

      final lost = reducer.reduce(connected, _event(CallEventType.mediaLost));

      expect(lost.snapshot.state, CallState.reconnecting);
      expect(lost.effects.map((effect) => effect.type), <CallEffectType>[
        CallEffectType.scheduleReconnectTimeout,
        CallEffectType.restartIce,
      ]);
      expect(
        lost.effects
            .singleWhere(
              (effect) =>
                  effect.type == CallEffectType.scheduleReconnectTimeout,
            )
            .delay,
        const Duration(seconds: 15),
      );
      expect(
        lost.effects.where(
          (effect) => effect.type == CallEffectType.restartIce,
        ),
        hasLength(1),
      );
    });

    test(
      'remote ICE restart is valid only while negotiating or reconnecting',
      () {
        const reducer = CallReducer();
        for (final state in <CallState>[
          CallState.negotiating,
          CallState.reconnecting,
        ]) {
          final snapshot = CallSessionSnapshot.active(
            callId: _callA,
            contactPeerId: 'contact-account-a',
            direction: CallDirection.outgoing,
            state: state,
            callerAccountPeerId: 'local-account',
            callerDeviceId: 'local-device',
            startedAt: _t0,
            acceptedAt: _t0,
          );
          final restart = reducer.reduce(
            snapshot,
            _event(
              CallEventType.remoteIceRestart,
              eventId: 'restart-${state.name}',
            ),
          );
          expect(
            restart.decision,
            CallEventDecision.applied,
            reason: state.name,
          );
          expect(restart.effects.map((effect) => effect.type), <CallEffectType>[
            CallEffectType.restartIce,
          ], reason: state.name);
        }

        final accepted = CallSessionSnapshot.active(
          callId: _callA,
          contactPeerId: 'contact-account-a',
          direction: CallDirection.outgoing,
          state: CallState.accepted,
          callerAccountPeerId: 'local-account',
          callerDeviceId: 'local-device',
          startedAt: _t0,
          acceptedAt: _t0,
        );
        final rejected = reducer.reduce(
          accepted,
          _event(
            CallEventType.remoteIceRestart,
            eventId: 'invalid-restart-accepted',
          ),
        );
        expect(rejected.decision, CallEventDecision.rejected);
        expect(rejected.effects, isEmpty);

        // A connected peer that did not notice the loss itself follows the
        // remote restart into reconnecting instead of rejecting it.
        final connected = CallSessionSnapshot.active(
          callId: _callA,
          contactPeerId: 'contact-account-a',
          direction: CallDirection.outgoing,
          state: CallState.connected,
          callerAccountPeerId: 'local-account',
          callerDeviceId: 'local-device',
          startedAt: _t0,
          acceptedAt: _t0,
          connectedAt: _t0,
        );
        final followed = reducer.reduce(
          connected,
          _event(
            CallEventType.remoteIceRestart,
            eventId: 'remote-restart-connected',
          ),
        );
        expect(followed.decision, CallEventDecision.applied);
        expect(followed.snapshot.state, CallState.reconnecting);
        expect(followed.effects.map((effect) => effect.type), <CallEffectType>[
          CallEffectType.scheduleReconnectTimeout,
          CallEffectType.restartIce,
        ]);

        // The callee never restarts on its own; it asks the caller.
        final calleeLost = reducer.reduce(
          CallSessionSnapshot.active(
            callId: _callA,
            contactPeerId: 'contact-account-a',
            direction: CallDirection.incoming,
            state: CallState.connected,
            callerAccountPeerId: 'contact-account-a',
            callerDeviceId: 'contact-device-a',
            startedAt: _t0,
            acceptedAt: _t0,
            connectedAt: _t0,
          ),
          _event(CallEventType.mediaLost, eventId: 'callee-media-lost'),
        );
        expect(calleeLost.snapshot.state, CallState.reconnecting);
        expect(
          calleeLost.effects.map((effect) => effect.type),
          <CallEffectType>[
            CallEffectType.scheduleReconnectTimeout,
            CallEffectType.requestIceRestart,
          ],
        );
      },
    );

    test('media recovery cancels the reconnect timer', () {
      const reducer = CallReducer();
      final reconnecting = CallSessionSnapshot.active(
        callId: _callA,
        contactPeerId: 'contact-account-a',
        direction: CallDirection.outgoing,
        state: CallState.reconnecting,
        callerAccountPeerId: 'local-account',
        callerDeviceId: 'local-device',
        startedAt: _t0,
        acceptedAt: _t0,
        connectedAt: _t0,
      );

      final recovered = reducer.reduce(
        reconnecting,
        _event(CallEventType.mediaRecovered),
      );

      expect(recovered.snapshot.state, CallState.connected);
      expect(recovered.effects.map((effect) => effect.type), <CallEffectType>[
        CallEffectType.cancelTimers,
      ]);
    });

    test('reconnecting accepts authenticated offer and answer effects', () {
      const reducer = CallReducer();
      final reconnecting = CallSessionSnapshot.active(
        callId: _callA,
        contactPeerId: 'contact-account-a',
        direction: CallDirection.outgoing,
        state: CallState.reconnecting,
        callerAccountPeerId: 'local-account',
        callerDeviceId: 'local-device',
        startedAt: _t0,
        acceptedAt: _t0,
        connectedAt: _t0,
      );

      final offer = reducer.reduce(
        reconnecting,
        _event(CallEventType.remoteOffer, eventId: 'restart-offer'),
      );
      final answer = reducer.reduce(
        reconnecting,
        _event(CallEventType.remoteAnswer, eventId: 'restart-answer'),
      );

      expect(offer.decision, CallEventDecision.applied);
      expect(offer.snapshot.state, CallState.reconnecting);
      expect(offer.effects.map((effect) => effect.type), <CallEffectType>[
        CallEffectType.deliverOffer,
      ]);
      expect(answer.decision, CallEventDecision.applied);
      expect(answer.snapshot.state, CallState.reconnecting);
      expect(answer.effects.map((effect) => effect.type), <CallEffectType>[
        CallEffectType.deliverAnswer,
      ]);
    });

    test('reconnect timeout terminalizes once', () {
      const reducer = CallReducer();
      final reconnecting = CallSessionSnapshot.active(
        callId: _callA,
        contactPeerId: 'contact-account-a',
        direction: CallDirection.outgoing,
        state: CallState.reconnecting,
        callerAccountPeerId: 'local-account',
        callerDeviceId: 'local-device',
        startedAt: _t0,
        acceptedAt: _t0,
        connectedAt: _t0,
      );
      final timedOut = reducer.reduce(
        reconnecting,
        _event(
          CallEventType.timeout,
          eventId: 'reconnect-timeout',
          timeoutKind: CallTimeoutKind.reconnect,
        ),
      );
      final lateTimeout = reducer.reduce(
        timedOut.snapshot,
        _event(
          CallEventType.timeout,
          eventId: 'late-reconnect-timeout',
          timeoutKind: CallTimeoutKind.reconnect,
        ),
      );

      expect(timedOut.snapshot.state, CallState.ended);
      expect(timedOut.snapshot.endReason, CallEndReason.reconnectFailed);
      expect(timedOut.terminalCleanupRequired, isTrue);
      expect(
        timedOut.effects.where(
          (effect) => effect.type == CallEffectType.cleanup,
        ),
        hasLength(1),
      );
      expect(lateTimeout.decision, CallEventDecision.ignored);
      expect(lateTimeout.reason, CallReductionReason.terminalDominates);
      expect(lateTimeout.terminalCleanupRequired, isFalse);
      expect(lateTimeout.effects, isEmpty);
    });

    test('offer and ICE remain unavailable before acceptance', () {
      const reducer = CallReducer();
      final inviting = _reduce(<CallEvent>[
        _event(CallEventType.place),
        _event(CallEventType.outgoingInviteReady),
      ]);

      final offer = reducer.reduce(
        inviting,
        _event(CallEventType.remoteOffer, eventId: 'early-offer'),
      );
      final ice = reducer.reduce(
        inviting,
        _event(
          CallEventType.remoteIce,
          eventId: 'early-ice',
          candidateId: 'early-ice',
        ),
      );

      expect(offer.decision, CallEventDecision.rejected);
      expect(offer.effects, isEmpty);
      expect(ice.decision, CallEventDecision.rejected);
      expect(ice.effects, isEmpty);
      expect(ice.snapshot.pendingCandidateIds, isEmpty);
    });

    test('terminal reason enum preserves the exact frozen wire grammar', () {
      expect(CallEndReason.values.map((reason) => reason.wireName), <String>[
        'declined',
        'busy',
        'caller_cancelled',
        'no_answer',
        'remote_hangup',
        'local_hangup',
        'permission_denied',
        'unsupported',
        'signaling_failed',
        'media_failed',
        'reconnect_failed',
        'expired',
        'app_shutdown',
        'policy_rejected',
      ]);
    });
  });

  group('network path readiness', () {
    const reducer = CallReducer();
    CallSessionSnapshot connected(CallDirection direction) =>
        CallSessionSnapshot.active(
          callId: _callA,
          contactPeerId: 'contact-account-a',
          direction: direction,
          state: CallState.connected,
          callerAccountPeerId: 'local-account',
          callerDeviceId: 'local-device',
          startedAt: _t0,
          acceptedAt: _t0,
          connectedAt: _t0,
        );
    CallEvent changed(int epoch, {String? id}) => _event(
      CallEventType.networkPathChanged,
      eventId: id ?? 'path-changed-$epoch',
      pathEpoch: epoch,
    );
    CallEvent ready(int epoch) => _event(
      CallEventType.networkPathReady,
      eventId: 'path-ready-$epoch',
      pathEpoch: epoch,
    );
    CallEvent failed(int epoch) => _event(
      CallEventType.networkPathFailed,
      eventId: 'path-failed-$epoch',
      pathEpoch: epoch,
    );
    CallEvent previousLost(int epoch, {String? id}) => _event(
      CallEventType.networkPreviousPathLost,
      eventId: id ?? 'path-previous-lost-$epoch',
      pathEpoch: epoch,
    );
    // A call that switched to epoch [epoch], restarted on relay readiness
    // and recovered media: the linger-end situation.
    CallSessionSnapshot recoveredOn(CallDirection direction, int epoch) {
      final waiting = reducer.reduce(connected(direction), changed(epoch));
      final restarted = reducer.reduce(waiting.snapshot, ready(epoch));
      final recovered = reducer.reduce(
        restarted.snapshot,
        _event(CallEventType.mediaRecovered, eventId: 'recovered-$epoch'),
      );
      expect(recovered.snapshot.state, CallState.connected);
      return recovered.snapshot;
    }

    List<CallEffectType> types(CallReduction reduction) =>
        reduction.effects.map((effect) => effect.type).toList();

    for (final direction in CallDirection.values) {
      test('relay readiness after a path change starts one proactive reconnect '
          'for ${direction.name}', () {
        final waiting = reducer.reduce(connected(direction), changed(7));
        expect(waiting.decision, CallEventDecision.applied);
        expect(waiting.snapshot.state, CallState.connected);
        expect(waiting.snapshot.pendingPathEpoch, 7);
        expect(waiting.effects, isEmpty);

        final restarted = reducer.reduce(waiting.snapshot, ready(7));
        expect(restarted.decision, CallEventDecision.applied);
        expect(restarted.snapshot.state, CallState.reconnecting);
        expect(restarted.snapshot.reconnectGeneration, 1);
        expect(restarted.snapshot.transportRecoveryRequired, isTrue);
        expect(restarted.snapshot.pendingPathEpoch, isNull);
        expect(types(restarted), <CallEffectType>[
          CallEffectType.scheduleReconnectTimeout,
          direction == CallDirection.incoming
              ? CallEffectType.requestIceRestart
              : CallEffectType.restartIce,
        ]);
        expect(restarted.effects.first.delay, const Duration(seconds: 15));
      });
    }

    test('relay failure launches no restart and discards its epoch', () {
      final waiting = reducer
          .reduce(connected(CallDirection.outgoing), changed(7))
          .snapshot;
      final failedOutcome = reducer.reduce(waiting, failed(7));
      expect(failedOutcome.decision, CallEventDecision.applied);
      expect(failedOutcome.snapshot.state, CallState.connected);
      expect(failedOutcome.snapshot.pendingPathEpoch, isNull);
      expect(failedOutcome.effects, isEmpty);

      final late = reducer.reduce(failedOutcome.snapshot, ready(7));
      expect(late.decision, CallEventDecision.ignored);
      expect(late.snapshot.state, CallState.connected);
      expect(late.effects, isEmpty);
    });

    test('readiness for an unknown or superseded epoch is ignored', () {
      final idleReady = reducer.reduce(
        connected(CallDirection.outgoing),
        ready(7),
      );
      expect(idleReady.decision, CallEventDecision.ignored);
      expect(idleReady.snapshot.state, CallState.connected);

      var snapshot = reducer
          .reduce(connected(CallDirection.outgoing), changed(7))
          .snapshot;
      snapshot = reducer.reduce(snapshot, changed(8)).snapshot;
      expect(snapshot.pendingPathEpoch, 8);
      final stale = reducer.reduce(snapshot, ready(7));
      expect(stale.decision, CallEventDecision.ignored);
      expect(stale.snapshot.state, CallState.connected);
      expect(stale.effects, isEmpty);

      final current = reducer.reduce(snapshot, ready(8));
      expect(current.snapshot.state, CallState.reconnecting);
      expect(current.snapshot.reconnectGeneration, 1);
    });

    test('a repeated change for the same epoch is a duplicate', () {
      final first = reducer.reduce(
        connected(CallDirection.outgoing),
        changed(7),
      );
      final again = reducer.reduce(
        first.snapshot,
        changed(7, id: 'path-changed-7-again'),
      );
      expect(again.decision, CallEventDecision.ignored);
      expect(again.snapshot.pendingPathEpoch, 7);
      expect(again.effects, isEmpty);
    });

    test('media loss during the path wait keeps its deadline and resumes '
        'sealed signals on readiness', () {
      final waiting = reducer
          .reduce(connected(CallDirection.outgoing), changed(7))
          .snapshot;
      final lost = reducer.reduce(waiting, _event(CallEventType.mediaLost));
      expect(lost.snapshot.state, CallState.reconnecting);
      expect(lost.snapshot.reconnectGeneration, 1);
      expect(lost.snapshot.pendingPathEpoch, 7);
      expect(types(lost), <CallEffectType>[
        CallEffectType.scheduleReconnectTimeout,
        CallEffectType.restartIce,
      ]);

      final resumed = reducer.reduce(lost.snapshot, ready(7));
      expect(resumed.decision, CallEventDecision.applied);
      expect(resumed.snapshot.state, CallState.reconnecting);
      expect(resumed.snapshot.reconnectGeneration, 1);
      expect(resumed.snapshot.pendingPathEpoch, isNull);
      expect(types(resumed), <CallEffectType>[
        CallEffectType.resumeRecoverySignals,
      ]);
    });

    test('path flaps during a reconnect episode never touch the deadline', () {
      final lost = reducer
          .reduce(
            connected(CallDirection.incoming),
            _event(CallEventType.mediaLost),
          )
          .snapshot;
      expect(lost.reconnectGeneration, 1);

      final flap1 = reducer.reduce(lost, changed(8));
      expect(flap1.effects, isEmpty);
      expect(flap1.snapshot.reconnectGeneration, 1);
      final flap2 = reducer.reduce(flap1.snapshot, changed(9));
      expect(flap2.effects, isEmpty);
      expect(flap2.snapshot.pendingPathEpoch, 9);

      final staleReady = reducer.reduce(flap2.snapshot, ready(8));
      expect(staleReady.decision, CallEventDecision.ignored);
      expect(staleReady.effects, isEmpty);

      final currentReady = reducer.reduce(flap2.snapshot, ready(9));
      expect(currentReady.snapshot.state, CallState.reconnecting);
      expect(currentReady.snapshot.reconnectGeneration, 1);
      expect(types(currentReady), <CallEffectType>[
        CallEffectType.resumeRecoverySignals,
      ]);
    });

    test('readiness cannot revive a call that ended during the wait', () {
      final waiting = reducer
          .reduce(connected(CallDirection.outgoing), changed(7))
          .snapshot;
      final hungUp = reducer.reduce(waiting, _event(CallEventType.end));
      expect(hungUp.snapshot.state, CallState.ended);
      final late = reducer.reduce(hungUp.snapshot, ready(7));
      expect(late.decision, CallEventDecision.ignored);
      expect(late.reason, CallReductionReason.terminalDominates);
      expect(late.snapshot.state, CallState.ended);
      expect(late.effects, isEmpty);

      final lost = reducer
          .reduce(waiting, _event(CallEventType.mediaLost))
          .snapshot;
      final expired = reducer.reduce(
        lost,
        _event(
          CallEventType.timeout,
          timeoutKind: CallTimeoutKind.reconnect,
          reconnectGeneration: lost.reconnectGeneration,
        ),
      );
      expect(expired.snapshot.state, CallState.ended);
      expect(expired.snapshot.endReason, CallEndReason.reconnectFailed);
      final afterExpiry = reducer.reduce(expired.snapshot, ready(7));
      expect(afterExpiry.decision, CallEventDecision.ignored);
      expect(afterExpiry.snapshot.state, CallState.ended);
      expect(afterExpiry.effects, isEmpty);
    });

    test('an idle session performs no ICE action for path events', () {
      final idle = CallSessionSnapshot.idle(now: _t0);
      for (final event in <CallEvent>[changed(7), ready(7), failed(7)]) {
        final reduction = reducer.reduce(idle, event);
        expect(reduction.decision, isNot(CallEventDecision.applied));
        expect(reduction.snapshot.state, CallState.idle);
        expect(reduction.effects, isEmpty);
      }
    });

    test('readiness while negotiating issues no second initial offer', () {
      final negotiating = CallSessionSnapshot.active(
        callId: _callA,
        contactPeerId: 'contact-account-a',
        direction: CallDirection.outgoing,
        state: CallState.negotiating,
        callerAccountPeerId: 'local-account',
        callerDeviceId: 'local-device',
        startedAt: _t0,
        acceptedAt: _t0,
      );
      final waiting = reducer.reduce(negotiating, changed(7));
      expect(waiting.decision, CallEventDecision.applied);
      expect(waiting.effects, isEmpty);
      final readyAgain = reducer.reduce(waiting.snapshot, ready(7));
      expect(readyAgain.decision, CallEventDecision.applied);
      expect(readyAgain.snapshot.state, CallState.negotiating);
      expect(readyAgain.snapshot.pendingPathEpoch, isNull);
      expect(readyAgain.effects, isEmpty);
    });

    for (final direction in CallDirection.values) {
      test('losing the previous network after recovery restarts at once '
          'for ${direction.name}', () {
        final recovered = recoveredOn(direction, 7);

        final lost = reducer.reduce(recovered, previousLost(7));

        expect(lost.decision, CallEventDecision.applied);
        expect(lost.snapshot.state, CallState.reconnecting);
        expect(lost.snapshot.reconnectGeneration, 2);
        expect(types(lost), <CallEffectType>[
          CallEffectType.scheduleReconnectTimeout,
          direction == CallDirection.incoming
              ? CallEffectType.requestIceRestart
              : CallEffectType.restartIce,
        ]);
        expect(lost.effects.first.delay, const Duration(seconds: 15));
      });
    }

    test('a previous-network loss during a reconnect episode coalesces', () {
      final waiting = reducer.reduce(
        connected(CallDirection.outgoing),
        changed(7),
      );
      final restarting = reducer.reduce(waiting.snapshot, ready(7)).snapshot;
      expect(restarting.state, CallState.reconnecting);

      final lost = reducer.reduce(restarting, previousLost(7));

      expect(lost.snapshot.state, CallState.reconnecting);
      expect(lost.snapshot.reconnectGeneration, restarting.reconnectGeneration);
      expect(lost.effects, isEmpty);
    });

    test('a previous-network loss is acted on once per epoch', () {
      final recovered = recoveredOn(CallDirection.outgoing, 7);
      final first = reducer.reduce(recovered, previousLost(7));
      final back = reducer.reduce(
        first.snapshot,
        _event(CallEventType.mediaRecovered, eventId: 'recovered-again'),
      );
      expect(back.snapshot.state, CallState.connected);

      final again = reducer.reduce(
        back.snapshot,
        previousLost(7, id: 'path-previous-lost-7-again'),
      );

      expect(again.decision, CallEventDecision.ignored);
      expect(again.snapshot.state, CallState.connected);
      expect(again.effects, isEmpty);
    });

    test(
      'a loss for a stale epoch, or with a newer path pending, does nothing',
      () {
        final recovered = recoveredOn(CallDirection.outgoing, 7);

        final stale = reducer.reduce(recovered, previousLost(6));
        expect(stale.decision, CallEventDecision.ignored);
        expect(stale.effects, isEmpty);

        final pending = reducer.reduce(recovered, changed(8)).snapshot;
        final whilePending = reducer.reduce(pending, previousLost(7));
        expect(whilePending.decision, CallEventDecision.ignored);
        expect(whilePending.snapshot.state, CallState.connected);
        expect(whilePending.snapshot.pendingPathEpoch, 8);
        expect(whilePending.effects, isEmpty);
      },
    );

    test('a loss before any ready epoch does nothing', () {
      final lost = reducer.reduce(
        connected(CallDirection.outgoing),
        previousLost(7),
      );
      expect(lost.decision, CallEventDecision.ignored);
      expect(lost.snapshot.state, CallState.connected);
      expect(lost.effects, isEmpty);
    });
  });
}
