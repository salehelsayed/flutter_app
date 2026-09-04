import '../data/call_history_repository.dart';
import '../domain/call_end_reason.dart';
import '../domain/call_session_snapshot.dart';
import '../domain/call_state.dart';

final class CallHistoryProjector {
  CallHistoryProjector(
    this.repository, {
    this.diagnosticsRouteAllowed = false,
    DateTime Function()? clock,
  }) : _clock = clock ?? _systemClock;

  final CallHistoryRepository repository;
  final bool diagnosticsRouteAllowed;
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
    if (existing != null) return existing;
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
    return await repository.getByCallId(entry.callId) ?? entry;
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
