import 'call_end_reason.dart';
import 'call_event.dart';
import 'call_session_snapshot.dart';

enum CallState {
  idle,
  preparing,
  inviting,
  incomingValidating,
  ringing,
  accepted,
  negotiating,
  connected,
  reconnecting,
  ending,
  ended,
}

enum CallEffectType {
  prepareOutgoingInvite,
  sendInvite,
  validateIncomingInvite,
  presentIncomingCall,
  sendRinging,
  sendAccept,
  sendReject,
  sendTerminate,
  sendBusy,
  scheduleNoAnswerTimeout,
  scheduleInviteExpiry,
  scheduleNegotiationTimeout,
  scheduleReconnectTimeout,
  cancelTimers,
  deliverOffer,
  deliverAnswer,
  queueIceCandidate,
  restartIce,
  requestIceRestart,
  prepareAcceptedMedia,
  startNegotiation,
  cleanup,
  projectHistory,
}

/// A payload-free instruction. External adapters bind any signaling bytes by
/// the event/call identity they already own, never through reducer state.
final class CallEffect {
  const CallEffect(this.type, {this.delay});

  final CallEffectType type;
  final Duration? delay;

  @override
  String toString() => 'CallEffect(${type.name})';
}

enum CallEventDecision { applied, ignored, rejected }

enum CallReductionReason {
  none,
  duplicateEvent,
  duplicateSession,
  terminalDominates,
  stateMismatch,
  wrongCall,
  invalidAdmission,
  expiredInvite,
  candidateQueueFull,
  effectQueueFull,
  busy,
  glareCanonicalCallWon,
  malformedEvent,
}

final class CallReduction {
  const CallReduction({
    required this.snapshot,
    required this.effects,
    required this.decision,
    required this.reason,
    required this.terminalCleanupRequired,
  });

  final CallSessionSnapshot snapshot;
  final List<CallEffect> effects;
  final CallEventDecision decision;
  final CallReductionReason reason;
  final bool terminalCleanupRequired;

  factory CallReduction.coordinatorDecision({
    required CallSessionSnapshot snapshot,
    required CallEventDecision decision,
    required CallReductionReason reason,
    List<CallEffect> effects = const <CallEffect>[],
  }) => CallReduction(
    snapshot: snapshot,
    effects: List<CallEffect>.unmodifiable(effects),
    decision: decision,
    reason: reason,
    terminalCleanupRequired: false,
  );
}

final class CallReducerPolicy {
  const CallReducerPolicy({
    this.recentEventCapacity = 64,
    this.candidateQueueCapacity = 64,
    this.effectQueueCapacity = 16,
    this.noAnswerTimeout = const Duration(seconds: 30),
    this.inviteLifetime = const Duration(seconds: 45),
    this.negotiationTimeout = const Duration(seconds: 30),
    this.reconnectTimeout = const Duration(seconds: 15),
  }) : assert(recentEventCapacity > 0),
       assert(candidateQueueCapacity > 0),
       assert(effectQueueCapacity > 0);

  final int recentEventCapacity;
  final int candidateQueueCapacity;
  final int effectQueueCapacity;
  final Duration noAnswerTimeout;
  final Duration inviteLifetime;
  final Duration negotiationTimeout;
  final Duration reconnectTimeout;
}

/// The only owner of call state transitions. It performs no I/O and reads no
/// ambient clock. Every decision depends only on [snapshot] and [event].
final class CallReducer {
  const CallReducer({this.policy = const CallReducerPolicy()});

  final CallReducerPolicy policy;

  CallReduction reduce(CallSessionSnapshot snapshot, CallEvent event) {
    if (snapshot.recentEventIds.contains(event.eventId)) {
      return _unchanged(
        snapshot,
        CallEventDecision.ignored,
        CallReductionReason.duplicateEvent,
      );
    }
    if (snapshot.isTerminal) {
      return _unchanged(
        snapshot,
        CallEventDecision.ignored,
        CallReductionReason.terminalDominates,
      );
    }
    if (!snapshot.isIdle &&
        event.callId != null &&
        event.callId != snapshot.callId) {
      return _unchanged(
        snapshot,
        CallEventDecision.rejected,
        CallReductionReason.wrongCall,
      );
    }

    if (snapshot.isIdle) return _reduceIdle(snapshot, event);

    if (event.type == CallEventType.appShutdown) {
      return _terminal(snapshot, event, CallEndReason.appShutdown);
    }
    if (event.type == CallEventType.glareLost) {
      return _terminal(snapshot, event, CallEndReason.callerCancelled);
    }
    if (event.type == CallEventType.remoteTerminate) {
      return _terminal(
        snapshot,
        event,
        event.endReason ?? CallEndReason.remoteHangup,
      );
    }
    if (event.type == CallEventType.remoteReject) {
      return _terminal(
        snapshot,
        event,
        event.endReason ?? CallEndReason.declined,
      );
    }
    if (event.type == CallEventType.directFailed) {
      return _apply(snapshot, event);
    }
    if (event.type == CallEventType.negotiationFailed) {
      return _terminal(
        snapshot,
        event,
        event.endReason ?? CallEndReason.mediaFailed,
      );
    }
    if (event.type == CallEventType.mailboxExpired) {
      if (_isPreconnect(snapshot.state)) {
        return _terminal(snapshot, event, CallEndReason.expired);
      }
      return _unchanged(
        snapshot,
        CallEventDecision.ignored,
        CallReductionReason.stateMismatch,
      );
    }
    if (event.type == CallEventType.timeout) {
      final kind = event.timeoutKind;
      if (kind == CallTimeoutKind.reconnect &&
          snapshot.state == CallState.reconnecting) {
        return _terminal(snapshot, event, CallEndReason.reconnectFailed);
      }
      if (kind == CallTimeoutKind.negotiation &&
          (snapshot.state == CallState.accepted ||
              snapshot.state == CallState.negotiating)) {
        return _terminal(snapshot, event, CallEndReason.mediaFailed);
      }
      if ((kind == CallTimeoutKind.noAnswer ||
              kind == CallTimeoutKind.inviteExpiry) &&
          _isPreconnect(snapshot.state)) {
        return _terminal(
          snapshot,
          event,
          kind == CallTimeoutKind.inviteExpiry
              ? CallEndReason.expired
              : CallEndReason.noAnswer,
        );
      }
      return _unchanged(
        snapshot,
        CallEventDecision.ignored,
        CallReductionReason.stateMismatch,
      );
    }
    if (event.type == CallEventType.cancel) {
      return _terminal(snapshot, event, CallEndReason.callerCancelled);
    }
    if (event.type == CallEventType.decline) {
      return _terminal(snapshot, event, CallEndReason.declined);
    }
    if (event.type == CallEventType.end) {
      return _terminal(snapshot, event, CallEndReason.localHangup);
    }
    if (event.type == CallEventType.nativeAction) {
      switch (event.nativeAction) {
        case CallNativeAction.answer:
          return _reduceState(snapshot, _asType(event, CallEventType.answer));
        case CallNativeAction.decline:
          return _terminal(
            snapshot,
            _asType(event, CallEventType.decline),
            CallEndReason.declined,
          );
        case CallNativeAction.end:
          return _terminal(
            snapshot,
            _asType(event, CallEventType.end),
            event.endReason ?? CallEndReason.localHangup,
          );
        case null:
          return _unchanged(
            snapshot,
            CallEventDecision.rejected,
            CallReductionReason.malformedEvent,
          );
      }
    }
    if (event.type == CallEventType.iceCandidateHandled) {
      final candidateId = event.candidateId;
      if (candidateId == null) {
        return _unchanged(
          snapshot,
          CallEventDecision.rejected,
          CallReductionReason.malformedEvent,
        );
      }
      if (!snapshot.pendingCandidateIds.contains(candidateId)) {
        return _stateMismatch(snapshot);
      }
      return _apply(
        snapshot.copyWith(
          pendingCandidateIds: snapshot.pendingCandidateIds
              .where((id) => id != candidateId)
              .toList(growable: false),
          recentCandidateIds: _appendEvent(
            snapshot.recentCandidateIds,
            candidateId,
          ),
        ),
        event,
      );
    }
    if (event.type == CallEventType.remoteIce) {
      if (!_canAcceptCandidate(snapshot.state)) {
        return _unchanged(
          snapshot,
          CallEventDecision.rejected,
          CallReductionReason.stateMismatch,
        );
      }
      return _queueCandidate(snapshot, event);
    }
    if (event.type == CallEventType.mailboxStored) {
      return _apply(
        snapshot.copyWith(
          mailboxCustodyConfirmed: true,
          transportRoute:
              event.transportRoute ?? CallRouteClass.ephemeralMailbox,
        ),
        event,
      );
    }
    if (event.type == CallEventType.wakeRequested) {
      // The relay alerted the callee's device, which also proves the signal
      // is in the mailbox. In `inviting` ring back now: a callee woken
      // headlessly signals nothing until it is answered.
      final custody = snapshot.copyWith(
        mailboxCustodyConfirmed: true,
        transportRoute: event.transportRoute ?? CallRouteClass.ephemeralMailbox,
      );
      if (snapshot.state == CallState.inviting) {
        return _transition(
          custody,
          event,
          CallState.ringing,
          ringingAt: event.occurredAt,
        );
      }
      return _apply(custody, event);
    }
    if (_isTransportReceipt(event.type)) {
      return _apply(snapshot, event);
    }
    return _reduceState(snapshot, event);
  }

  CallReduction _reduceIdle(CallSessionSnapshot idle, CallEvent event) {
    if (event.type == CallEventType.appShutdown) {
      return _unchanged(
        idle,
        CallEventDecision.ignored,
        CallReductionReason.stateMismatch,
      );
    }
    if (event.type == CallEventType.place) {
      if (!_hasSessionFields(event, outgoing: true)) {
        return _unchanged(
          idle,
          CallEventDecision.rejected,
          CallReductionReason.malformedEvent,
        );
      }
      final snapshot = CallSessionSnapshot.active(
        callId: event.callId!,
        contactPeerId: event.contactPeerId!,
        direction: CallDirection.outgoing,
        state: CallState.preparing,
        callerAccountPeerId: event.localAccountPeerId!,
        callerDeviceId: event.localDeviceId!,
        startedAt: event.occurredAt,
        observedAt: event.occurredAt,
        transportRoute: event.transportRoute,
        recentEventIds: _appendEvent(const <String>[], event.eventId),
      );
      return _withEffects(snapshot, const <CallEffect>[
        CallEffect(CallEffectType.prepareOutgoingInvite),
      ]);
    }
    if (event.type == CallEventType.remoteInvite) {
      if (event.admission != IncomingCallAdmission.accepted) {
        return _unchanged(
          idle,
          CallEventDecision.rejected,
          CallReductionReason.invalidAdmission,
        );
      }
      if (!_hasSessionFields(event, outgoing: false)) {
        return _unchanged(
          idle,
          CallEventDecision.rejected,
          CallReductionReason.malformedEvent,
        );
      }
      final expired =
          event.expiresAt != null &&
          !event.occurredAt.isBefore(event.expiresAt!);
      final snapshot = CallSessionSnapshot.active(
        callId: event.callId!,
        contactPeerId: event.contactPeerId!,
        direction: CallDirection.incoming,
        state: expired ? CallState.ended : CallState.incomingValidating,
        callerAccountPeerId: event.remoteAccountPeerId!,
        callerDeviceId: event.remoteDeviceId!,
        startedAt: event.occurredAt,
        observedAt: event.occurredAt,
        endedAt: expired ? event.occurredAt : null,
        endReason: expired ? CallEndReason.expired : null,
        transportRoute: event.transportRoute,
        recentEventIds: _appendEvent(const <String>[], event.eventId),
      );
      if (expired) {
        return _withEffects(
          snapshot,
          _boundedEffects(const <CallEffect>[
            CallEffect(CallEffectType.cleanup),
            CallEffect(CallEffectType.projectHistory),
          ]),
          terminalCleanupRequired: true,
          reason: CallReductionReason.expiredInvite,
        );
      }
      final incomingEffects = <CallEffect>[
        const CallEffect(CallEffectType.validateIncomingInvite),
        CallEffect(
          CallEffectType.scheduleInviteExpiry,
          delay: event.expiresAt == null
              ? policy.inviteLifetime
              : event.expiresAt!.difference(event.occurredAt),
        ),
      ];
      if (incomingEffects.length > policy.effectQueueCapacity) {
        return _unchanged(
          idle,
          CallEventDecision.rejected,
          CallReductionReason.effectQueueFull,
        );
      }
      return _withEffects(snapshot, incomingEffects);
    }
    return _unchanged(
      idle,
      CallEventDecision.rejected,
      CallReductionReason.stateMismatch,
    );
  }

  CallReduction _reduceState(CallSessionSnapshot snapshot, CallEvent event) {
    switch (snapshot.state) {
      case CallState.preparing:
        if (event.type == CallEventType.outgoingInviteReady) {
          return _transition(
            snapshot,
            event,
            CallState.inviting,
            effects: <CallEffect>[
              CallEffect(
                CallEffectType.scheduleNoAnswerTimeout,
                delay: policy.noAnswerTimeout,
              ),
              CallEffect(
                CallEffectType.scheduleInviteExpiry,
                delay: policy.inviteLifetime,
              ),
              const CallEffect(CallEffectType.sendInvite),
            ],
          );
        }
        return _stateMismatch(snapshot);
      case CallState.inviting:
        if (event.type == CallEventType.remoteRinging) {
          return _transition(
            snapshot,
            event,
            CallState.ringing,
            ringingAt: event.occurredAt,
          );
        }
        if (event.type == CallEventType.remoteAccept) {
          return _transition(
            snapshot,
            event,
            CallState.accepted,
            effects: <CallEffect>[
              const CallEffect(CallEffectType.cancelTimers),
              CallEffect(
                CallEffectType.scheduleNegotiationTimeout,
                delay: policy.negotiationTimeout,
              ),
              const CallEffect(CallEffectType.startNegotiation),
            ],
            acceptedAt: event.occurredAt,
          );
        }
        if (event.type == CallEventType.remoteAnswer ||
            event.type == CallEventType.answer) {
          return _stateMismatch(snapshot);
        }
        return _stateMismatch(snapshot);
      case CallState.incomingValidating:
        if (event.type == CallEventType.incomingValidated) {
          return _apply(
            snapshot.copyWith(incomingValidated: true),
            event,
            effects: const <CallEffect>[
              CallEffect(CallEffectType.presentIncomingCall),
            ],
          );
        }
        if (event.type == CallEventType.systemUiPresented) {
          if (!snapshot.incomingValidated) return _stateMismatch(snapshot);
          return _transition(
            snapshot,
            event,
            CallState.ringing,
            effects: const <CallEffect>[CallEffect(CallEffectType.sendRinging)],
            ringingAt: event.occurredAt,
          );
        }
        if (event.type == CallEventType.remoteInvite) {
          return _unchanged(
            snapshot,
            CallEventDecision.ignored,
            CallReductionReason.duplicateSession,
          );
        }
        if (event.type == CallEventType.answer ||
            event.type == CallEventType.remoteAnswer) {
          return _stateMismatch(snapshot);
        }
        return _stateMismatch(snapshot);
      case CallState.ringing:
        if (event.type == CallEventType.remoteAccept &&
            snapshot.direction == CallDirection.outgoing) {
          return _transition(
            snapshot,
            event,
            CallState.accepted,
            effects: <CallEffect>[
              const CallEffect(CallEffectType.cancelTimers),
              CallEffect(
                CallEffectType.scheduleNegotiationTimeout,
                delay: policy.negotiationTimeout,
              ),
              const CallEffect(CallEffectType.startNegotiation),
            ],
            acceptedAt: event.occurredAt,
          );
        }
        if (event.type == CallEventType.answer &&
            snapshot.direction == CallDirection.incoming) {
          return _transition(
            snapshot,
            event,
            CallState.accepted,
            effects: <CallEffect>[
              const CallEffect(CallEffectType.cancelTimers),
              CallEffect(
                CallEffectType.scheduleNegotiationTimeout,
                delay: policy.negotiationTimeout,
              ),
              const CallEffect(CallEffectType.prepareAcceptedMedia),
              const CallEffect(CallEffectType.sendAccept),
            ],
            acceptedAt: event.occurredAt,
          );
        }
        if (event.type == CallEventType.systemUiPresented ||
            event.type == CallEventType.remoteRinging) {
          return _unchanged(
            snapshot,
            CallEventDecision.ignored,
            CallReductionReason.duplicateSession,
          );
        }
        return _stateMismatch(snapshot);
      case CallState.accepted:
        if (event.type == CallEventType.negotiationReady ||
            event.type == CallEventType.remoteOffer) {
          final effect = event.type == CallEventType.remoteOffer
              ? CallEffectType.deliverOffer
              : CallEffectType.startNegotiation;
          return _transition(
            snapshot,
            event,
            CallState.negotiating,
            effects: <CallEffect>[CallEffect(effect)],
          );
        }
        return _stateMismatch(snapshot);
      case CallState.negotiating:
        if (event.type == CallEventType.remoteAnswer) {
          return _apply(
            snapshot,
            event,
            effects: const <CallEffect>[
              CallEffect(CallEffectType.deliverAnswer),
            ],
          );
        }
        if (event.type == CallEventType.remoteIceRestart) {
          return _apply(
            snapshot,
            event,
            effects: const <CallEffect>[CallEffect(CallEffectType.restartIce)],
          );
        }
        if (event.type == CallEventType.mediaConnected) {
          return _transition(
            snapshot,
            event,
            CallState.connected,
            effects: const <CallEffect>[
              CallEffect(CallEffectType.cancelTimers),
            ],
            connectedAt: event.occurredAt,
          );
        }
        return _stateMismatch(snapshot);
      case CallState.connected:
        if (event.type == CallEventType.remoteOffer &&
            snapshot.direction == CallDirection.incoming) {
          // Independent signaling paths can deliver the caller's restart
          // offer before its announcement or this peer's media-loss callback.
          // The negotiation executor verifies and mirrors its ICE generation.
          return _transition(
            snapshot,
            event,
            CallState.reconnecting,
            effects: <CallEffect>[
              CallEffect(
                CallEffectType.scheduleReconnectTimeout,
                delay: policy.reconnectTimeout,
              ),
              const CallEffect(CallEffectType.deliverOffer),
            ],
          );
        }
        if (event.type == CallEventType.mediaLost) {
          // The caller owns ICE restarts so two simultaneous restarts can
          // never collide. The callee asks the caller to restart instead.
          return _transition(
            snapshot,
            event,
            CallState.reconnecting,
            effects: <CallEffect>[
              CallEffect(
                snapshot.direction == CallDirection.incoming
                    ? CallEffectType.requestIceRestart
                    : CallEffectType.restartIce,
              ),
              CallEffect(
                CallEffectType.scheduleReconnectTimeout,
                delay: policy.reconnectTimeout,
              ),
            ],
          );
        }
        if (event.type == CallEventType.remoteIceRestart) {
          // The peer noticed the loss first. Its announcement (or request)
          // starts this side's reconnect instead of being rejected.
          return _transition(
            snapshot,
            event,
            CallState.reconnecting,
            effects: <CallEffect>[
              const CallEffect(CallEffectType.restartIce),
              CallEffect(
                CallEffectType.scheduleReconnectTimeout,
                delay: policy.reconnectTimeout,
              ),
            ],
          );
        }
        return _stateMismatch(snapshot);
      case CallState.reconnecting:
        if (event.type == CallEventType.remoteOffer ||
            event.type == CallEventType.remoteAnswer) {
          return _apply(
            snapshot,
            event,
            effects: <CallEffect>[
              CallEffect(
                event.type == CallEventType.remoteOffer
                    ? CallEffectType.deliverOffer
                    : CallEffectType.deliverAnswer,
              ),
            ],
          );
        }
        if (event.type == CallEventType.remoteIceRestart) {
          return _apply(
            snapshot,
            event,
            effects: const <CallEffect>[CallEffect(CallEffectType.restartIce)],
          );
        }
        if (event.type == CallEventType.mediaRecovered ||
            event.type == CallEventType.mediaConnected) {
          return _transition(
            snapshot,
            event,
            CallState.connected,
            effects: const <CallEffect>[
              CallEffect(CallEffectType.cancelTimers),
            ],
          );
        }
        return _stateMismatch(snapshot);
      case CallState.ending:
      case CallState.ended:
      case CallState.idle:
        return _stateMismatch(snapshot);
    }
  }

  CallReduction _queueCandidate(CallSessionSnapshot snapshot, CallEvent event) {
    final candidateId = event.candidateId;
    if (candidateId == null) {
      return _unchanged(
        snapshot,
        CallEventDecision.rejected,
        CallReductionReason.malformedEvent,
      );
    }
    if (snapshot.pendingCandidateIds.contains(candidateId) ||
        snapshot.recentCandidateIds.contains(candidateId)) {
      return _unchanged(
        snapshot,
        CallEventDecision.ignored,
        CallReductionReason.duplicateEvent,
      );
    }
    if (snapshot.pendingCandidateIds.length >= policy.candidateQueueCapacity) {
      return _unchanged(
        snapshot,
        CallEventDecision.rejected,
        CallReductionReason.candidateQueueFull,
      );
    }
    return _apply(
      snapshot.copyWith(
        pendingCandidateIds: <String>[
          ...snapshot.pendingCandidateIds,
          candidateId,
        ],
      ),
      event,
      effects: const <CallEffect>[CallEffect(CallEffectType.queueIceCandidate)],
    );
  }

  CallReduction _terminal(
    CallSessionSnapshot snapshot,
    CallEvent event,
    CallEndReason reason,
  ) {
    final occurredAt = _monotonicEventTime(snapshot, event.occurredAt);
    final signalEffect = switch (event.type) {
      CallEventType.decline => CallEffectType.sendReject,
      CallEventType.cancel ||
      CallEventType.end ||
      CallEventType.appShutdown ||
      CallEventType.negotiationFailed ||
      CallEventType.timeout => CallEffectType.sendTerminate,
      _ => null,
    };
    final effects = <CallEffect>[
      const CallEffect(CallEffectType.cancelTimers),
      if (signalEffect != null) CallEffect(signalEffect),
      const CallEffect(CallEffectType.cleanup),
      const CallEffect(CallEffectType.projectHistory),
    ];
    return _withEffects(
      snapshot.copyWith(
        state: CallState.ended,
        observedAt: occurredAt,
        endedAt: occurredAt,
        endReason: reason,
        recentEventIds: _appendEvent(snapshot.recentEventIds, event.eventId),
      ),
      _boundedEffects(effects),
      terminalCleanupRequired: true,
    );
  }

  CallReduction _transition(
    CallSessionSnapshot snapshot,
    CallEvent event,
    CallState state, {
    List<CallEffect> effects = const <CallEffect>[],
    DateTime? ringingAt,
    DateTime? acceptedAt,
    DateTime? connectedAt,
  }) {
    if (effects.length > policy.effectQueueCapacity) {
      return _unchanged(
        snapshot,
        CallEventDecision.rejected,
        CallReductionReason.effectQueueFull,
      );
    }
    var occurredAt = _monotonicEventTime(snapshot, event.occurredAt);
    for (final milestone in <DateTime?>[ringingAt, acceptedAt, connectedAt]) {
      if (milestone != null && occurredAt.isBefore(milestone)) {
        occurredAt = milestone.toUtc();
      }
    }
    return _withEffects(
      snapshot.copyWith(
        state: state,
        observedAt: occurredAt,
        ringingAt: ringingAt == null
            ? snapshot.ringingAt
            : _notBefore(ringingAt, occurredAt),
        acceptedAt: acceptedAt == null
            ? snapshot.acceptedAt
            : _notBefore(acceptedAt, occurredAt),
        connectedAt: connectedAt == null
            ? snapshot.connectedAt
            : _notBefore(connectedAt, occurredAt),
        transportRoute: event.transportRoute ?? snapshot.transportRoute,
        recentEventIds: _appendEvent(snapshot.recentEventIds, event.eventId),
      ),
      effects,
    );
  }

  CallReduction _apply(
    CallSessionSnapshot snapshot,
    CallEvent event, {
    List<CallEffect> effects = const <CallEffect>[],
  }) {
    if (effects.length > policy.effectQueueCapacity) {
      return _unchanged(
        snapshot,
        CallEventDecision.rejected,
        CallReductionReason.effectQueueFull,
      );
    }
    final occurredAt = _monotonicEventTime(snapshot, event.occurredAt);
    return _withEffects(
      snapshot.copyWith(
        observedAt: occurredAt,
        transportRoute: event.transportRoute ?? snapshot.transportRoute,
        recentEventIds: _appendEvent(snapshot.recentEventIds, event.eventId),
      ),
      effects,
    );
  }

  DateTime _monotonicEventTime(
    CallSessionSnapshot snapshot,
    DateTime eventTime,
  ) {
    var result = eventTime.toUtc();
    for (final timestamp in <DateTime?>[
      snapshot.startedAt,
      snapshot.ringingAt,
      snapshot.acceptedAt,
      snapshot.connectedAt,
      snapshot.endedAt,
      snapshot.observedAt,
    ]) {
      if (timestamp != null && result.isBefore(timestamp)) {
        result = timestamp;
      }
    }
    return result;
  }

  DateTime _notBefore(DateTime value, DateTime floor) {
    final normalized = value.toUtc();
    return normalized.isBefore(floor) ? floor : normalized;
  }

  CallReduction _withEffects(
    CallSessionSnapshot snapshot,
    List<CallEffect> effects, {
    bool terminalCleanupRequired = false,
    CallReductionReason reason = CallReductionReason.none,
  }) {
    return CallReduction(
      snapshot: snapshot,
      effects: List<CallEffect>.unmodifiable(effects),
      decision: CallEventDecision.applied,
      reason: reason,
      terminalCleanupRequired: terminalCleanupRequired,
    );
  }

  CallReduction _stateMismatch(CallSessionSnapshot snapshot) => _unchanged(
    snapshot,
    CallEventDecision.rejected,
    CallReductionReason.stateMismatch,
  );

  CallReduction _unchanged(
    CallSessionSnapshot snapshot,
    CallEventDecision decision,
    CallReductionReason reason,
  ) => CallReduction(
    snapshot: snapshot,
    effects: const <CallEffect>[],
    decision: decision,
    reason: reason,
    terminalCleanupRequired: false,
  );

  List<String> _appendEvent(List<String> ids, String id) {
    final result = <String>[...ids, id];
    if (result.length > policy.recentEventCapacity) {
      result.removeRange(0, result.length - policy.recentEventCapacity);
    }
    return result;
  }

  static bool _hasSessionFields(CallEvent event, {required bool outgoing}) =>
      event.callId != null &&
      (event.contactPeerId?.trim().isNotEmpty ?? false) &&
      (outgoing
          ? (event.localAccountPeerId?.trim().isNotEmpty ?? false) &&
                (event.localDeviceId?.trim().isNotEmpty ?? false)
          : (event.remoteAccountPeerId?.trim().isNotEmpty ?? false) &&
                (event.remoteDeviceId?.trim().isNotEmpty ?? false));

  static bool _isTransportReceipt(CallEventType type) => switch (type) {
    CallEventType.directAccepted ||
    CallEventType.mailboxStored ||
    CallEventType.mailboxRetrieved ||
    CallEventType.mailboxAcked ||
    CallEventType.wakeRequested => true,
    _ => false,
  };

  List<CallEffect> _boundedEffects(List<CallEffect> effects) =>
      effects.length <= policy.effectQueueCapacity
      ? effects
      : effects.sublist(0, policy.effectQueueCapacity);

  static bool _isPreconnect(CallState state) => switch (state) {
    CallState.preparing ||
    CallState.inviting ||
    CallState.incomingValidating ||
    CallState.ringing => true,
    _ => false,
  };

  static bool _canAcceptCandidate(CallState state) => switch (state) {
    CallState.accepted ||
    CallState.negotiating ||
    CallState.connected ||
    CallState.reconnecting => true,
    _ => false,
  };

  static CallEvent _asType(CallEvent event, CallEventType type) => CallEvent(
    type: type,
    eventId: event.eventId,
    occurredAt: event.occurredAt,
    callId: event.callId,
    contactPeerId: event.contactPeerId,
    localAccountPeerId: event.localAccountPeerId,
    localDeviceId: event.localDeviceId,
    remoteAccountPeerId: event.remoteAccountPeerId,
    remoteDeviceId: event.remoteDeviceId,
    expiresAt: event.expiresAt,
    admission: event.admission,
    timeoutKind: event.timeoutKind,
    nativeAction: event.nativeAction,
    endReason: event.endReason,
    candidateId: event.candidateId,
    transportRoute: event.transportRoute,
  );
}
