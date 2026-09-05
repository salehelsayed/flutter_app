import '../data/call_history_repository.dart';
import '../domain/call_end_reason.dart';
import '../domain/call_session_snapshot.dart';
import '../domain/call_state.dart';

final class CallHistoryProjector {
  CallHistoryProjector(
    this.repository, {
    this.diagnosticsRouteAllowed = false,
    this.onTerminalProjected,
    DateTime Function()? clock,
  }) : _clock = clock ?? _systemClock;

  final CallHistoryRepository repository;
  final bool diagnosticsRouteAllowed;

  /// 405: fired AFTER a terminal row is durable, so a conversation that is
  /// already on screen can re-read the table. The order matters: the
  /// coordinator publishes its terminal snapshot before this projection runs,
  /// so a listener bound to the snapshot would read the table too early and
  /// still see nothing.
  final void Function(CallHistoryEntry entry, bool inserted)?
  onTerminalProjected;

  final DateTime Function() _clock;

  Future<CallHistoryEntry> projectTerminal(CallSessionSnapshot snapshot) async {
    if (snapshot.state != CallState.ended ||
        snapshot.callId == null ||
        snapshot.contactPeerId == null ||
        snapshot.direction == null ||
        snapshot.startedAt == null ||
        snapshot.endedAt == null ||
        snapshot.endReason == null) {
      throw StateError('only a complete terminal call can enter history');
    }
    final existing = await repository.getByCallId(snapshot.callId!);
    if (existing != null) {
      _announce(existing, false);
      return existing;
    }
    final now = _clock().toUtc();
    final entry = CallHistoryEntry(
      callId: snapshot.callId!,
      contactAccountPeerId: snapshot.contactPeerId!,
      direction: snapshot.direction!,
      terminalReason: snapshot.endReason!,
      status: _status(snapshot),
      startedAt: snapshot.startedAt!,
      connectedAt: snapshot.connectedAt,
      endedAt: snapshot.endedAt!,
      transportRoute: diagnosticsRouteAllowed ? snapshot.transportRoute : null,
      createdAt: now,
      updatedAt: now,
    );
    await repository.upsertTerminal(entry);
    final stored = await repository.getByCallId(entry.callId) ?? entry;
    _announce(stored, true);
    return stored;
  }

  /// A listener is presentation, never custody: it can never fail a call.
  void _announce(CallHistoryEntry entry, bool inserted) {
    final listener = onTerminalProjected;
    if (listener == null) return;
    try {
      listener(entry, inserted);
    } catch (_) {
      // The projection is already durable; a broken listener changes nothing.
    }
  }

  /// Conversation projection order is chronological and deterministic. The
  /// repository may keep a newest-first storage order for paging.
  Future<List<CallHistoryEntry>> timelineForContact(
    String contactAccountPeerId,
  ) async {
    final entries = <CallHistoryEntry>[
      ...await repository.listForContact(contactAccountPeerId),
    ];
    entries.sort((left, right) {
      final byTime = left.startedAt.compareTo(right.startedAt);
      return byTime != 0
          ? byTime
          : left.callId.value.compareTo(right.callId.value);
    });
    return List<CallHistoryEntry>.unmodifiable(entries);
  }

  static CallHistoryStatus _status(CallSessionSnapshot snapshot) {
    switch (snapshot.endReason!) {
      case CallEndReason.expired:
        return CallHistoryStatus.missed;
      case CallEndReason.noAnswer:
        return CallHistoryStatus.missed;
      case CallEndReason.declined:
        return CallHistoryStatus.declined;
      case CallEndReason.callerCancelled:
        return CallHistoryStatus.cancelled;
      case CallEndReason.busy:
        return CallHistoryStatus.busy;
      case CallEndReason.localHangup:
        if (snapshot.connectedAt != null) return CallHistoryStatus.completed;
        // Hung up before media connected: the caller cancelled, the callee
        // declined.
        return snapshot.direction == CallDirection.outgoing
            ? CallHistoryStatus.cancelled
            : CallHistoryStatus.declined;
      case CallEndReason.remoteHangup:
        if (snapshot.connectedAt != null) return CallHistoryStatus.completed;
        // The peer hung up before media connected: the callee missed it, the
        // caller was declined.
        return snapshot.direction == CallDirection.incoming
            ? CallHistoryStatus.missed
            : CallHistoryStatus.declined;
      case CallEndReason.appShutdown:
        return snapshot.connectedAt == null
            ? CallHistoryStatus.failed
            : CallHistoryStatus.completed;
      case CallEndReason.permissionDenied:
      case CallEndReason.unsupported:
      case CallEndReason.signalingFailed:
      case CallEndReason.mediaFailed:
      case CallEndReason.reconnectFailed:
      case CallEndReason.policyRejected:
        return CallHistoryStatus.failed;
    }
  }

  static DateTime _systemClock() => DateTime.now().toUtc();
}
