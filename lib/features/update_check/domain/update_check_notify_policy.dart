/// T4a background notification rules for the SE-41 update check. Pure Dart:
/// the caller supplies the decision from `UpdateCheckService.check()`, the
/// stored state, the time and the device facts.
library;

import 'update_check_models.dart';
import 'update_check_state.dart';

/// One notification per kind. A new one of the same kind replaces the last.
enum UpdateNotifyKind {
  soft('soft'),
  hard('hard');

  const UpdateNotifyKind(this.wireName);

  final String wireName;
}

/// Which built-in text to show. Only `security` has its own copy.
enum UpdateNotifyCopy { general, security }

/// Hard reminders: the first, then daily for [hardDailyReminders] days, then
/// weekly.
const int hardDailyReminders = 7;

/// Why nothing is posted.
enum UpdateNotifySkip {
  /// No update, or the installed build is current.
  noUpdate,

  /// The app is in the foreground: T2 shows the banner or the overlay.
  foreground,

  /// A call is ringing or active. Try again on the next run.
  inCall,

  /// Already posted for this latestBuild, or the next hard reminder is not
  /// due yet.
  notDue,
}

sealed class UpdateNotifyPlan {
  const UpdateNotifyPlan();
}

final class UpdateNotifyPlanSkip extends UpdateNotifyPlan {
  const UpdateNotifyPlanSkip(this.reason);

  final UpdateNotifySkip reason;

  @override
  bool operator ==(Object other) =>
      other is UpdateNotifyPlanSkip && other.reason == reason;

  @override
  int get hashCode => reason.hashCode;

  @override
  String toString() => 'UpdateNotifyPlan.skip(${reason.name})';
}

final class UpdateNotifyPlanPost extends UpdateNotifyPlan {
  const UpdateNotifyPlanPost({
    required this.kind,
    required this.copy,
    required this.record,
  });

  final UpdateNotifyKind kind;
  final UpdateNotifyCopy copy;

  /// The state fields to save once the notification was actually posted.
  /// The store merges them by max.
  final UpdateCheckState Function(UpdateCheckState state) record;

  @override
  String toString() => 'UpdateNotifyPlan.post(${kind.name}, ${copy.name})';
}

UpdateNotifyCopy updateNotifyCopyFor(UpdateReasonCode code) =>
    code == UpdateReasonCode.security
    ? UpdateNotifyCopy.security
    : UpdateNotifyCopy.general;

/// Soft (installed < latestBuild): once per latestBuild.
/// Hard (installed < minBuild): once, then daily x7, then weekly; only a
/// higher minBuild starts over. A clock that went back (now < lastHardNotifyAt)
/// makes the reminder due. Never in the foreground or during a call.
UpdateNotifyPlan planUpdateNotification({
  required UpdateDecision decision,
  required UpdateCheckState state,
  required DateTime now,
  required bool foreground,
  required bool inCall,
}) {
  if (decision is UpdateDecisionNone) {
    return const UpdateNotifyPlanSkip(UpdateNotifySkip.noUpdate);
  }
  if (foreground) return const UpdateNotifyPlanSkip(UpdateNotifySkip.foreground);
  if (inCall) return const UpdateNotifyPlanSkip(UpdateNotifySkip.inCall);
  switch (decision) {
    case UpdateDecisionNone():
      return const UpdateNotifyPlanSkip(UpdateNotifySkip.noUpdate);
    case UpdateDecisionSoft(:final latestBuild, :final reasonCode):
      final notified = state.notifiedSoftLatestBuild;
      if (notified != null && notified >= latestBuild) {
        return const UpdateNotifyPlanSkip(UpdateNotifySkip.notDue);
      }
      return UpdateNotifyPlanPost(
        kind: UpdateNotifyKind.soft,
        copy: updateNotifyCopyFor(reasonCode),
        record: (s) => s.copyWith(notifiedSoftLatestBuild: latestBuild),
      );
    case UpdateDecisionHard(:final minBuild, :final reasonCode):
      // Only a HIGHER minBuild starts a new episode. A lowered minBuild stays
      // in the stored episode: the store merges the hard fields by max, so a
      // record for a lower minBuild would be dropped and every run would post.
      final notified = state.notifiedHardMinBuild;
      final sameEpisode = notified != null && notified >= minBuild;
      final episode = sameEpisode ? notified : minBuild;
      final count = sameEpisode ? state.hardReminderCount : 0;
      final last = sameEpisode ? state.lastHardNotifyAt : null;
      if (count > 0 && last != null && !_hardReminderDue(count, last, now)) {
        return const UpdateNotifyPlanSkip(UpdateNotifySkip.notDue);
      }
      return UpdateNotifyPlanPost(
        kind: UpdateNotifyKind.hard,
        copy: updateNotifyCopyFor(reasonCode),
        record: (s) => s.copyWith(
          notifiedHardMinBuild: episode,
          hardReminderCount: count + 1,
          lastHardNotifyAt: now,
        ),
      );
  }
}

/// [count] hard notifications were posted, the last at [last]. The 2nd to
/// the 8th come a day apart; after that a week apart.
bool _hardReminderDue(int count, DateTime last, DateTime now) {
  if (now.isBefore(last)) return true;
  final interval = count <= hardDailyReminders
      ? const Duration(days: 1)
      : const Duration(days: 7);
  return now.difference(last) >= interval;
}
