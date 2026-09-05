import '../data/call_history_repository.dart';
import '../domain/call_end_reason.dart';
import '../domain/call_session_snapshot.dart';
import '../domain/call_signal.dart';
import '../domain/call_state.dart';
import 'call_history_projector.dart';
import 'missed_call_notifier.dart';

/// 408: the one place the killed-app path turns a terminal call into what the
/// user sees — the chat row and the missed-call card.
///
/// The card is AWAITED on purpose. The headless isolate tears down as soon as
/// its session finishes, so a fire-and-forget post would race that teardown
/// and the user would get nothing for exactly the call they were least able to
/// notice.
///
/// [invite] is absent when an earlier run acknowledged the invite row and only
/// the terminal row remains; the terminal signal alone still carries the
/// caller's identity and the call id.
Future<void> recordHeadlessTerminalCall({
  required CallHistoryRepository repository,
  required CallHistoryProjector projector,
  required MissedCallNotifier notifier,
  required CallSignal terminal,
  required CallEndReason reason,
  CallSignal? invite,
}) async {
  final startedAtMs = invite?.createdAtMs ?? terminal.createdAtMs;
  // Clock skew between the two devices can put the terminate before the
  // invite, and CallHistoryEntry refuses a non-monotonic pair.
  final endedAtMs = terminal.createdAtMs < startedAtMs
      ? startedAtMs
      : terminal.createdAtMs;

  // Read before projecting: the projection is idempotent, and only a first
  // insert may tell the user. A replay must not raise a second card.
  final alreadyStored = await repository.getByCallId(terminal.callId) != null;

  final entry = await projector.projectTerminal(
    CallSessionSnapshot.active(
      callId: terminal.callId,
      contactPeerId: terminal.senderAccountPeerId,
      direction: CallDirection.incoming,
      state: CallState.ended,
      callerAccountPeerId: terminal.senderAccountPeerId,
      callerDeviceId: terminal.senderDevicePeerId,
      startedAt: DateTime.fromMillisecondsSinceEpoch(startedAtMs, isUtc: true),
      endedAt: DateTime.fromMillisecondsSinceEpoch(endedAtMs, isUtc: true),
      endReason: reason,
    ),
  );

  await notifier.notifyTerminal(entry, inserted: !alreadyStored);
}
