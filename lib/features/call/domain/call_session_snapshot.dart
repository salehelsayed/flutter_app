import 'call_end_reason.dart';
import 'call_id.dart';
import 'call_state.dart' show CallState;

enum CallDirection { outgoing, incoming }

/// Coarse route data. It may be persisted only with explicit diagnostics
/// consent. No endpoint, address, handle, or token belongs here.
enum CallRouteClass { direct, circuitRelay, ephemeralMailbox }

extension CallRouteClassWire on CallRouteClass {
  String get wireName => switch (this) {
    CallRouteClass.direct => 'direct',
    CallRouteClass.circuitRelay => 'circuit_relay',
    CallRouteClass.ephemeralMailbox => 'ephemeral_mailbox',
  };

  static CallRouteClass parse(String value) => switch (value) {
    'direct' => CallRouteClass.direct,
    'circuit_relay' => CallRouteClass.circuitRelay,
    'ephemeral_mailbox' => CallRouteClass.ephemeralMailbox,
    _ => throw const FormatException('unsupported call route class'),
  };
}

/// Immutable reducer-owned state for one call leg.
final class CallSessionSnapshot {
  CallSessionSnapshot._({
    required this.state,
    required this.observedAt,
    required this.callId,
    required this.contactPeerId,
    required this.direction,
    required this.callerAccountPeerId,
    required this.callerDeviceId,
    required this.startedAt,
    required this.ringingAt,
    required this.acceptedAt,
    required this.connectedAt,
    required this.endedAt,
    required this.endReason,
    required this.transportRoute,
    required this.incomingValidated,
    required this.mailboxCustodyConfirmed,
    required List<String> recentEventIds,
    required List<String> pendingCandidateIds,
    required List<String> recentCandidateIds,
  }) : recentEventIds = List<String>.unmodifiable(recentEventIds),
       pendingCandidateIds = List<String>.unmodifiable(pendingCandidateIds),
       recentCandidateIds = List<String>.unmodifiable(recentCandidateIds);

  factory CallSessionSnapshot.idle({required DateTime now}) =>
      CallSessionSnapshot._(
        state: CallState.idle,
        observedAt: now.toUtc(),
        callId: null,
        contactPeerId: null,
        direction: null,
        callerAccountPeerId: null,
        callerDeviceId: null,
        startedAt: null,
        ringingAt: null,
        acceptedAt: null,
        connectedAt: null,
        endedAt: null,
        endReason: null,
        transportRoute: null,
        incomingValidated: false,
        mailboxCustodyConfirmed: false,
        recentEventIds: const <String>[],
        pendingCandidateIds: const <String>[],
        recentCandidateIds: const <String>[],
      );

  factory CallSessionSnapshot.active({
    required CallId callId,
    required String contactPeerId,
    required CallDirection direction,
    required CallState state,
    required String callerAccountPeerId,
    required String callerDeviceId,
    required DateTime startedAt,
    DateTime? observedAt,
    DateTime? ringingAt,
    DateTime? acceptedAt,
    DateTime? connectedAt,
    DateTime? endedAt,
    CallEndReason? endReason,
    CallRouteClass? transportRoute,
    bool incomingValidated = false,
    bool mailboxCustodyConfirmed = false,
    List<String> recentEventIds = const <String>[],
    List<String> pendingCandidateIds = const <String>[],
    List<String> recentCandidateIds = const <String>[],
  }) {
    if (state == CallState.idle) {
      throw ArgumentError.value(state, 'state', 'active call cannot be idle');
    }
    if (contactPeerId.trim().isEmpty ||
        callerAccountPeerId.trim().isEmpty ||
        callerDeviceId.trim().isEmpty) {
      throw ArgumentError('active call identities must be non-empty');
    }
    if (state == CallState.ended && (endedAt == null || endReason == null)) {
      throw ArgumentError('ended call requires endedAt and endReason');
    }
    return CallSessionSnapshot._(
      state: state,
      observedAt: (observedAt ?? endedAt ?? startedAt).toUtc(),
      callId: callId,
      contactPeerId: contactPeerId,
      direction: direction,
      callerAccountPeerId: callerAccountPeerId,
      callerDeviceId: callerDeviceId,
      startedAt: startedAt.toUtc(),
      ringingAt: ringingAt?.toUtc(),
      acceptedAt: acceptedAt?.toUtc(),
      connectedAt: connectedAt?.toUtc(),
      endedAt: endedAt?.toUtc(),
      endReason: endReason,
      transportRoute: transportRoute,
      incomingValidated: incomingValidated,
      mailboxCustodyConfirmed: mailboxCustodyConfirmed,
      recentEventIds: recentEventIds,
      pendingCandidateIds: pendingCandidateIds,
      recentCandidateIds: recentCandidateIds,
    );
  }

  final CallState state;
  final DateTime observedAt;
  final CallId? callId;
  final String? contactPeerId;
  final CallDirection? direction;
  final String? callerAccountPeerId;
  final String? callerDeviceId;
  final DateTime? startedAt;
  final DateTime? ringingAt;
  final DateTime? acceptedAt;
  final DateTime? connectedAt;
  final DateTime? endedAt;
  final CallEndReason? endReason;
  final CallRouteClass? transportRoute;
  final bool incomingValidated;
  final bool mailboxCustodyConfirmed;
  final List<String> recentEventIds;

  /// Candidates awaiting handoff to the bounded media executor.
  final List<String> pendingCandidateIds;

  /// Bounded deduplication history, independent of pending work capacity.
  final List<String> recentCandidateIds;

  bool get isIdle => state == CallState.idle;
  bool get isTerminal => state == CallState.ended;

  String? get glareTuple {
    final id = callId;
    final account = callerAccountPeerId;
    if (id == null || account == null) return null;
    return '${id.value}\u0000$account';
  }

  CallSessionSnapshot copyWith({
    CallState? state,
    DateTime? observedAt,
    Object? ringingAt = _unset,
    Object? acceptedAt = _unset,
    Object? connectedAt = _unset,
    Object? endedAt = _unset,
    Object? endReason = _unset,
    Object? transportRoute = _unset,
    bool? incomingValidated,
    bool? mailboxCustodyConfirmed,
    List<String>? recentEventIds,
    List<String>? pendingCandidateIds,
    List<String>? recentCandidateIds,
  }) => CallSessionSnapshot._(
    state: state ?? this.state,
    observedAt: (observedAt ?? this.observedAt).toUtc(),
    callId: callId,
    contactPeerId: contactPeerId,
    direction: direction,
    callerAccountPeerId: callerAccountPeerId,
    callerDeviceId: callerDeviceId,
    startedAt: startedAt,
    ringingAt: identical(ringingAt, _unset)
        ? this.ringingAt
        : (ringingAt as DateTime?)?.toUtc(),
    acceptedAt: identical(acceptedAt, _unset)
        ? this.acceptedAt
        : (acceptedAt as DateTime?)?.toUtc(),
    connectedAt: identical(connectedAt, _unset)
        ? this.connectedAt
        : (connectedAt as DateTime?)?.toUtc(),
    endedAt: identical(endedAt, _unset)
        ? this.endedAt
        : (endedAt as DateTime?)?.toUtc(),
    endReason: identical(endReason, _unset)
        ? this.endReason
        : endReason as CallEndReason?,
    transportRoute: identical(transportRoute, _unset)
        ? this.transportRoute
        : transportRoute as CallRouteClass?,
    incomingValidated: incomingValidated ?? this.incomingValidated,
    mailboxCustodyConfirmed:
        mailboxCustodyConfirmed ?? this.mailboxCustodyConfirmed,
    recentEventIds: recentEventIds ?? this.recentEventIds,
    pendingCandidateIds: pendingCandidateIds ?? this.pendingCandidateIds,
    recentCandidateIds: recentCandidateIds ?? this.recentCandidateIds,
  );

  Map<String, Object?> toDiagnosticMap() => <String, Object?>{
    'state': state.name,
    'direction': direction?.name,
    'endReason': endReason?.name,
    'transportRoute': transportRoute?.name,
    'incomingValidated': incomingValidated,
    'mailboxCustodyConfirmed': mailboxCustodyConfirmed,
    'pendingCandidateCount': pendingCandidateIds.length,
  };

  @override
  String toString() => 'CallSessionSnapshot(${toDiagnosticMap()})';
}

const Object _unset = Object();
