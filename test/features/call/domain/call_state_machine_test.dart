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
        CallEffectType.restartIce,
        CallEffectType.scheduleReconnectTimeout,
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
          CallEffectType.restartIce,
          CallEffectType.scheduleReconnectTimeout,
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
        expect(calleeLost.effects.map((effect) => effect.type), <CallEffectType>[
          CallEffectType.requestIceRestart,
          CallEffectType.scheduleReconnectTimeout,
        ]);
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
}
