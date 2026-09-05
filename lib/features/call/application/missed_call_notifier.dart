import 'package:flutter_app/features/call/data/call_history_repository.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

/// 406: tells the user about a call they never took.
///
/// Neither platform does this for us. Android runs self-managed Telecom
/// (`androidx.core.telecom.CallsManager`), which never writes the system call
/// log and posts no missed-call notification. iOS CallKit reports a remote
/// cancel as `.remoteEnded`, which reads as an ordinary ended call in Recents.
/// So the app is the only thing that can surface it.

/// Posts the card. Kept as a narrow function so the notifier owns policy and
/// nothing else.
typedef PostMissedCallNotification =
    Future<void> Function({
      required String contactAccountPeerId,
      required String title,
      required String body,
    });

/// Resolves the caller's display name; null when the contact is unknown.
typedef ResolveMissedCallContactName =
    Future<String?> Function(String contactAccountPeerId);

/// True when this conversation is visible right now, so a card would be noise:
/// the call row already appears live in the open chat.
typedef MissedCallNotificationSuppressed =
    Future<bool> Function(String contactAccountPeerId);

final class MissedCallNotifier {
  const MissedCallNotifier({
    required this.post,
    required this.resolveContactName,
    required this.isSuppressed,
    required this.missedBody,
    required this.unknownCallerTitle,
  });

  final PostMissedCallNotification post;
  final ResolveMissedCallContactName resolveContactName;
  final MissedCallNotificationSuppressed isSuppressed;

  /// Localized copy, resolved by the composition root: this runs in
  /// background isolates with no widget tree to read a delegate from.
  final String missedBody;
  final String unknownCallerTitle;

  /// Statuses that mean "the user never took this call". `declined` is
  /// deliberately absent: the user acted, and telling them about their own
  /// decision is noise.
  static const _notifiable = <CallHistoryStatus>{
    CallHistoryStatus.missed,
    CallHistoryStatus.cancelled,
    CallHistoryStatus.busy,
  };

  /// Returns true when a card was posted. Never throws: a call must not fail
  /// because a notification could not be shown.
  Future<bool> notifyTerminal(
    CallHistoryEntry entry, {
    required bool inserted,
  }) async {
    if (!inserted) return false;
    if (entry.direction != CallDirection.incoming) return false;
    if (!_notifiable.contains(entry.status)) return false;

    final contactAccountPeerId = entry.contactAccountPeerId;
    try {
      if (await isSuppressed(contactAccountPeerId)) {
        emitFlowEvent(
          layer: 'FL',
          event: 'MISSED_CALL_NOTIFICATION_SUPPRESSED',
          details: {'status': entry.status.name},
        );
        return false;
      }
    } catch (_) {
      // An unreadable visibility answer must not silence a missed call.
    }

    String? name;
    try {
      name = await resolveContactName(contactAccountPeerId);
    } catch (_) {
      name = null;
    }
    final title = (name == null || name.trim().isEmpty)
        ? unknownCallerTitle
        : name.trim();

    try {
      await post(
        contactAccountPeerId: contactAccountPeerId,
        title: title,
        body: missedBody,
      );
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'MISSED_CALL_NOTIFICATION_FAILED',
        details: {'errorType': error.runtimeType.toString()},
      );
      return false;
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'MISSED_CALL_NOTIFICATION_SHOWN',
      details: {'status': entry.status.name},
    );
    return true;
  }
}
