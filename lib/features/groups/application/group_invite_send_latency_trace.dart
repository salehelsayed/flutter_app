import 'package:uuid/uuid.dart';

/// Caller surfaces covered by the TC-267 invite-send latency baseline.
enum GroupInviteLatencyPath {
  create('create'),
  add('add');

  const GroupInviteLatencyPath(this.wireName);

  final String wireName;
}

/// Await boundaries recorded by the TC-267 diagnostic trace.
enum GroupInviteLatencyPhase {
  preFanout('pre_fanout'),
  sign('sign'),
  encrypt('encrypt'),
  live('live'),
  inbox('inbox'),
  persistence('persistence'),
  navigationSettlement('navigation_settlement');

  const GroupInviteLatencyPhase(this.wireName);

  final String wireName;
}

enum GroupInviteLatencyBoundary {
  begin('begin'),
  end('end');

  const GroupInviteLatencyBoundary(this.wireName);

  final String wireName;
}

typedef GroupInviteLatencyEventSink =
    void Function(GroupInviteLatencyEvent event);

/// A diagnostic-only event. The sink is absent in normal application runs.
///
/// No payload, key material, ciphertext, or address is admitted here. The
/// envelope is represented only by its SHA-256 discriminator at the send
/// boundary.
final class GroupInviteLatencyEvent {
  const GroupInviteLatencyEvent({
    required this.operationId,
    required this.path,
    required this.phase,
    required this.boundary,
    required this.at,
    this.groupId,
    this.inviteId,
    this.recipientPeerId,
    this.details = const <String, Object?>{},
  });

  final String operationId;
  final GroupInviteLatencyPath path;
  final GroupInviteLatencyPhase phase;
  final GroupInviteLatencyBoundary boundary;
  final DateTime at;
  final String? groupId;
  final String? inviteId;
  final String? recipientPeerId;
  final Map<String, Object?> details;

  Map<String, Object?> toJson() => <String, Object?>{
    'operationId': operationId,
    'path': path.wireName,
    'phase': phase.wireName,
    'boundary': boundary.wireName,
    'at': at.toUtc().toIso8601String(),
    if (groupId != null) 'groupId': groupId,
    if (inviteId != null) 'inviteId': inviteId,
    if (recipientPeerId != null) 'recipientPeerId': recipientPeerId,
    if (details.isNotEmpty) 'details': details,
  };
}

final List<_GroupInviteLatencySinkRegistration> _inviteLatencySinkStack =
    <_GroupInviteLatencySinkRegistration>[];
const _latencyUuid = Uuid();

final class _GroupInviteLatencySinkRegistration {
  const _GroupInviteLatencySinkRegistration(this.sink);

  final GroupInviteLatencyEventSink sink;
}

/// Owner-scoped installation used only by evidence harnesses and tests.
final class GroupInviteLatencySinkLease {
  GroupInviteLatencySinkLease._(this._registration);

  final _GroupInviteLatencySinkRegistration _registration;
  bool _released = false;

  void release() {
    if (_released) return;
    _released = true;
    _inviteLatencySinkStack.remove(_registration);
  }
}

GroupInviteLatencySinkLease installGroupInviteLatencySink(
  GroupInviteLatencyEventSink sink,
) {
  final registration = _GroupInviteLatencySinkRegistration(sink);
  _inviteLatencySinkStack.add(registration);
  return GroupInviteLatencySinkLease._(registration);
}

/// Starts a trace only when an evidence sink is installed. Production callers
/// can invoke this unconditionally; it is a no-op allocation-wise by default.
GroupInviteLatencyTrace? maybeStartGroupInviteLatencyTrace({
  required GroupInviteLatencyPath path,
  String? operationId,
  DateTime Function()? now,
}) {
  if (_inviteLatencySinkStack.isEmpty) return null;
  final sink = _inviteLatencySinkStack.last.sink;
  return GroupInviteLatencyTrace.start(
    operationId: operationId ?? _latencyUuid.v4(),
    path: path,
    sink: sink,
    now: now,
  );
}

/// Correlates one create/add caller with its target invite awaits.
///
/// Sink failures are deliberately swallowed: diagnostic collection must never
/// alter delivery or navigation behavior.
final class GroupInviteLatencyTrace {
  GroupInviteLatencyTrace._({
    required this.operationId,
    required this.path,
    required GroupInviteLatencyEventSink sink,
    required DateTime Function() now,
  }) : _sink = sink,
       _now = now;

  factory GroupInviteLatencyTrace.start({
    required String operationId,
    required GroupInviteLatencyPath path,
    required GroupInviteLatencyEventSink sink,
    DateTime Function()? now,
  }) {
    final normalizedOperationId = operationId.trim();
    if (normalizedOperationId.isEmpty) {
      throw ArgumentError.value(
        operationId,
        'operationId',
        'must not be empty',
      );
    }
    final trace = GroupInviteLatencyTrace._(
      operationId: normalizedOperationId,
      path: path,
      sink: sink,
      now: now ?? _utcNow,
    );
    trace.begin(GroupInviteLatencyPhase.preFanout);
    return trace;
  }

  final String operationId;
  final GroupInviteLatencyPath path;
  final GroupInviteLatencyEventSink _sink;
  final DateTime Function() _now;
  bool _preFanoutEnded = false;
  bool _navigationSettlementStarted = false;
  bool _navigationSettlementEnded = false;

  /// The pre-fanout window belongs to the caller operation, not each expanded
  /// recipient/device target. Only the first ready/failure target closes it.
  void endPreFanout({
    String? groupId,
    String? inviteId,
    String? recipientPeerId,
    required String outcome,
  }) {
    if (_preFanoutEnded) return;
    _preFanoutEnded = true;
    end(
      GroupInviteLatencyPhase.preFanout,
      groupId: groupId,
      inviteId: inviteId,
      recipientPeerId: recipientPeerId,
      outcome: outcome,
    );
  }

  /// Create starts caller settlement before its final result reload; add starts
  /// it immediately before pop. Repeated UI/application calls share one pair.
  void beginNavigationSettlement({required String groupId}) {
    if (_navigationSettlementStarted) return;
    _navigationSettlementStarted = true;
    begin(GroupInviteLatencyPhase.navigationSettlement, groupId: groupId);
  }

  void endNavigationSettlement({
    required String groupId,
    required String outcome,
  }) {
    if (_navigationSettlementEnded) return;
    beginNavigationSettlement(groupId: groupId);
    _navigationSettlementEnded = true;
    end(
      GroupInviteLatencyPhase.navigationSettlement,
      groupId: groupId,
      outcome: outcome,
    );
  }

  void begin(
    GroupInviteLatencyPhase phase, {
    String? groupId,
    String? inviteId,
    String? recipientPeerId,
    Map<String, Object?> details = const <String, Object?>{},
  }) {
    _emit(
      phase: phase,
      boundary: GroupInviteLatencyBoundary.begin,
      groupId: groupId,
      inviteId: inviteId,
      recipientPeerId: recipientPeerId,
      details: details,
    );
  }

  void end(
    GroupInviteLatencyPhase phase, {
    String? groupId,
    String? inviteId,
    String? recipientPeerId,
    required String outcome,
    Map<String, Object?> details = const <String, Object?>{},
  }) {
    _emit(
      phase: phase,
      boundary: GroupInviteLatencyBoundary.end,
      groupId: groupId,
      inviteId: inviteId,
      recipientPeerId: recipientPeerId,
      details: <String, Object?>{'outcome': outcome, ...details},
    );
  }

  /// Emits a delimiter pair without claiming that an await occurred.
  void skip(
    GroupInviteLatencyPhase phase, {
    String? groupId,
    String? inviteId,
    String? recipientPeerId,
    Map<String, Object?> details = const <String, Object?>{},
  }) {
    try {
      final at = _now().toUtc();
      _emitAt(
        phase: phase,
        boundary: GroupInviteLatencyBoundary.begin,
        at: at,
        groupId: groupId,
        inviteId: inviteId,
        recipientPeerId: recipientPeerId,
        details: details,
      );
      _emitAt(
        phase: phase,
        boundary: GroupInviteLatencyBoundary.end,
        at: at,
        groupId: groupId,
        inviteId: inviteId,
        recipientPeerId: recipientPeerId,
        details: <String, Object?>{'outcome': 'skipped', ...details},
      );
    } catch (_) {
      // Diagnostic clocks are injectable test/evidence seams and must be as
      // isolated from production behavior as the sink itself.
    }
  }

  void _emit({
    required GroupInviteLatencyPhase phase,
    required GroupInviteLatencyBoundary boundary,
    String? groupId,
    String? inviteId,
    String? recipientPeerId,
    Map<String, Object?> details = const <String, Object?>{},
  }) {
    try {
      _emitAt(
        phase: phase,
        boundary: boundary,
        at: _now().toUtc(),
        groupId: groupId,
        inviteId: inviteId,
        recipientPeerId: recipientPeerId,
        details: details,
      );
    } catch (_) {
      // Diagnostic clocks are injectable test/evidence seams and must be as
      // isolated from production behavior as the sink itself.
    }
  }

  void _emitAt({
    required GroupInviteLatencyPhase phase,
    required GroupInviteLatencyBoundary boundary,
    required DateTime at,
    String? groupId,
    String? inviteId,
    String? recipientPeerId,
    Map<String, Object?> details = const <String, Object?>{},
  }) {
    try {
      _sink(
        GroupInviteLatencyEvent(
          operationId: operationId,
          path: path,
          phase: phase,
          boundary: boundary,
          at: at,
          groupId: groupId,
          inviteId: inviteId,
          recipientPeerId: recipientPeerId,
          details: Map<String, Object?>.unmodifiable(details),
        ),
      );
    } catch (_) {
      // Evidence collection cannot become a production failure path.
    }
  }
}

DateTime _utcNow() => DateTime.now().toUtc();
