import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';

/// 118 Phase 4: enforces "at most one audible tone per conversation per
/// [window]". The FIRST live (non-recovery, non-viewing, non-deduped,
/// non-muted) message after a quiet window plays a tone; every subsequent
/// message for that conversation within the window updates silently.
///
/// In-memory and foreground/live-only — it does NOT survive the FCM background
/// isolate / iOS NSE, so background notifications are not debounced by it
/// (OQ-4). Mirrors the [ActiveConversationTracker] pattern with an injectable
/// clock for deterministic tests.
class NotificationToneTracker {
  final DateTime Function() _clock;
  final Duration window;
  final Map<String, DateTime> _lastToneAt = {};

  NotificationToneTracker({
    DateTime Function()? clock,
    this.window = const Duration(seconds: 10),
  }) : _clock = clock ?? DateTime.now;

  /// Returns true (and records the tone time) when [conversationKey] may play
  /// an audible tone now: the first message, or the first after a [window] of
  /// silence. Returns false within the window (the caller should show silently).
  ///
  /// The key is normalized via [ActiveConversationTracker.normalizeActiveKey]
  /// so a group's anchored route (`group:<id>|message:<id>`) and its bare group
  /// key (`group:<id>`) bucket together — keying on the raw route would make
  /// every group message sound.
  ///
  /// The window is anchored to the last AUDIBLE tone and does NOT extend on
  /// silent updates, so a tone fires roughly every [window] of continuous
  /// activity and again immediately after a lull.
  bool shouldPlayTone(String conversationKey) {
    final key = ActiveConversationTracker.normalizeActiveKey(conversationKey);
    final now = _clock();
    final last = _lastToneAt[key];
    if (last != null && now.difference(last) < window) {
      return false;
    }
    _lastToneAt[key] = now;
    return true;
  }
}
