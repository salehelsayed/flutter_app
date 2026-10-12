import 'dart:async';
import 'dart:ui' show Locale;

import '../application/update_check_service.dart';
import '../domain/update_check_models.dart';
import '../domain/update_check_notify_policy.dart';
import '../domain/update_check_policy.dart';
import '../domain/update_check_state.dart';
import '../infrastructure/update_check_state_store.dart';
import 'update_check_notifier.dart';

/// What one background run did. The wire names go to native code.
enum UpdateCheckBackgroundOutcome {
  /// The kill switch is off. Native code cancels the schedule.
  disabled,

  /// The state file cannot be read (iOS before the first unlock). Nothing ran
  /// and nothing was written.
  stateUnavailable,

  /// The budget ran out. Nothing was written after that point.
  aborted,
  noUpdate,
  foreground,
  inCall,
  notDue,

  /// Notifications are not allowed. Skipped silently, nothing recorded.
  notPermitted,
  notified,
  failed,
}

final class UpdateCheckBackgroundResult {
  const UpdateCheckBackgroundResult(this.outcome, {this.checked = false});

  final UpdateCheckBackgroundOutcome outcome;

  /// True when this run downloaded the version file.
  final bool checked;

  bool get enabled => outcome != UpdateCheckBackgroundOutcome.disabled;

  Map<String, Object?> toWire() => {
    'outcome': outcome.name,
    'enabled': enabled,
    'checked': checked,
  };
}

/// The one Dart entry of the T4a background check, for the iOS BG task, the
/// Android main-engine handoff and the Android minimal engine.
///
/// Authority: only [UpdateCheckService.check] and the signed file decide. The
/// run needs no first frame and never awaits the Go bridge, SQLCipher or the
/// app bootstrap. It reads the state, runs the check when one is due (the
/// same 6 h gate as the foreground, failed downloads included), then applies
/// [planUpdateNotification].
class UpdateCheckBackgroundRunner {
  UpdateCheckBackgroundRunner({
    required UpdateCheckService service,
    required UpdateCheckStateStore store,
    required UpdateNotificationPoster poster,
    required Future<bool> Function() isForeground,
    required Future<bool> Function() isInCall,
    DateTime Function()? clock,
    Locale? locale,
  }) : _service = service,
       _store = store,
       _poster = poster,
       _isForeground = isForeground,
       _isInCall = isInCall,
       _clock = clock ?? DateTime.now,
       _locale = locale;

  final UpdateCheckService _service;
  final UpdateCheckStateStore _store;
  final UpdateNotificationPoster _poster;
  final Future<bool> Function() _isForeground;
  final Future<bool> Function() _isInCall;
  final DateTime Function() _clock;
  final Locale? _locale;

  /// Runs once within [budget]. When the budget runs out the result is
  /// [UpdateCheckBackgroundOutcome.aborted] and the run writes nothing more.
  /// Every write is a whole-file merge and rename, so none is ever partial.
  Future<UpdateCheckBackgroundResult> run({
    required String reason,
    required Duration budget,
  }) async {
    if (!_service.isEnabled) {
      return const UpdateCheckBackgroundResult(
        UpdateCheckBackgroundOutcome.disabled,
      );
    }
    var expired = false;
    try {
      return await _run(() => expired).timeout(
        budget,
        onTimeout: () {
          expired = true;
          return const UpdateCheckBackgroundResult(
            UpdateCheckBackgroundOutcome.aborted,
          );
        },
      );
    } catch (_) {
      return const UpdateCheckBackgroundResult(
        UpdateCheckBackgroundOutcome.failed,
      );
    }
  }

  Future<UpdateCheckBackgroundResult> _run(bool Function() expired) async {
    const aborted = UpdateCheckBackgroundResult(
      UpdateCheckBackgroundOutcome.aborted,
    );
    final before = await _loadOrNull();
    if (before == null) {
      return const UpdateCheckBackgroundResult(
        UpdateCheckBackgroundOutcome.stateUnavailable,
      );
    }
    final due = isUpdateCheckDue(
      now: _clock(),
      lastCheckAt: before.lastCheckAt,
      checkedThisLaunch: true,
    );
    final decision = due
        ? await _service.check()
        : await _service.decideFromStored();
    if (expired()) return aborted;

    UpdateCheckBackgroundResult result(UpdateCheckBackgroundOutcome outcome) =>
        UpdateCheckBackgroundResult(outcome, checked: due);

    if (decision is UpdateDecisionNone) {
      return result(UpdateCheckBackgroundOutcome.noUpdate);
    }
    final state = await _loadOrNull();
    if (state == null) {
      return result(UpdateCheckBackgroundOutcome.stateUnavailable);
    }
    final plan = planUpdateNotification(
      decision: decision,
      state: state,
      now: _clock(),
      foreground: await _isForeground(),
      inCall: await _isInCall(),
    );
    if (expired()) return aborted;
    switch (plan) {
      case UpdateNotifyPlanSkip(:final reason):
        return result(switch (reason) {
          UpdateNotifySkip.noUpdate => UpdateCheckBackgroundOutcome.noUpdate,
          UpdateNotifySkip.foreground =>
            UpdateCheckBackgroundOutcome.foreground,
          UpdateNotifySkip.inCall => UpdateCheckBackgroundOutcome.inCall,
          UpdateNotifySkip.notDue => UpdateCheckBackgroundOutcome.notDue,
        });
      case UpdateNotifyPlanPost():
        final text = updateNotificationText(plan.copy, locale: _locale);
        final posted = await _poster.post(
          kind: plan.kind,
          title: text.title,
          body: text.body,
        );
        if (!posted) return result(UpdateCheckBackgroundOutcome.notPermitted);
        if (expired()) return aborted;
        try {
          await _store.save(plan.record(state));
        } catch (_) {
          // Posted but not recorded: the next run may post the same
          // notification again, which replaces this one (same id).
        }
        return result(UpdateCheckBackgroundOutcome.notified);
    }
  }

  Future<UpdateCheckState?> _loadOrNull() async {
    try {
      return await _store.load();
    } on UpdateCheckStateUnavailable {
      return null;
    }
  }
}
