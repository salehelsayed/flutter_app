import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_app/features/push/domain/push_registration_health.dart';

enum PushRegistrationHealthAction { none, retry, openNotificationSettings }

@immutable
final class PushRegistrationHealthViewModel {
  const PushRegistrationHealthViewModel({
    required this.phase,
    required this.reason,
    required this.warningVisible,
    required this.action,
  });

  const PushRegistrationHealthViewModel.neutral()
    : phase = null,
      reason = PushRegistrationHealthReason.none,
      warningVisible = false,
      action = PushRegistrationHealthAction.none;

  final PushRegistrationHealthPhase? phase;
  final PushRegistrationHealthReason reason;
  final bool warningVisible;
  final PushRegistrationHealthAction action;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is PushRegistrationHealthViewModel &&
            other.phase == phase &&
            other.reason == reason &&
            other.warningVisible == warningVisible &&
            other.action == action;
  }

  @override
  int get hashCode => Object.hash(phase, reason, warningVisible, action);
}

final class PushRegistrationHealthNotifier
    extends ValueNotifier<PushRegistrationHealthViewModel> {
  PushRegistrationHealthNotifier({
    DateTime Function()? now,
    this.failureThreshold = 3,
    this.warningAfter = const Duration(hours: 24),
  }) : _now = now ?? DateTime.now,
       super(const PushRegistrationHealthViewModel.neutral()) {
    if (failureThreshold <= 0) {
      throw ArgumentError.value(
        failureThreshold,
        'failureThreshold',
        'must be positive',
      );
    }
  }

  final DateTime Function() _now;
  final int failureThreshold;
  final Duration warningAfter;
  PushRegistrationHealthRecord? _record;
  Timer? _thresholdTimer;

  PushRegistrationHealthRecord? get record => _record;

  void publish(PushRegistrationHealthRecord record) {
    _record = record;
    _thresholdTimer?.cancel();
    _thresholdTimer = null;
    _publishCurrent();
    _scheduleThresholdIfNeeded();
  }

  void clear() {
    _record = null;
    _thresholdTimer?.cancel();
    _thresholdTimer = null;
    value = const PushRegistrationHealthViewModel.neutral();
  }

  void _publishCurrent() {
    final current = _record;
    if (current == null) {
      value = const PushRegistrationHealthViewModel.neutral();
      return;
    }
    final visible = current.warningVisibleAt(
      _now(),
      failureThreshold: failureThreshold,
      warningAfter: warningAfter,
    );
    final action = !visible
        ? PushRegistrationHealthAction.none
        : current.reason == PushRegistrationHealthReason.permissionDenied
        ? PushRegistrationHealthAction.openNotificationSettings
        : PushRegistrationHealthAction.retry;
    value = PushRegistrationHealthViewModel(
      phase: current.phase,
      reason: current.reason,
      warningVisible: visible,
      action: action,
    );
  }

  void _scheduleThresholdIfNeeded() {
    final current = _record;
    final warningSince = current?.transientWarningSince;
    if (current == null ||
        warningSince == null ||
        !current.reason.isTransient ||
        current.consecutiveFailures >= failureThreshold ||
        value.warningVisible) {
      return;
    }
    final remaining = warningSince.add(warningAfter).difference(_now().toUtc());
    if (remaining <= Duration.zero) {
      _publishCurrent();
      return;
    }
    _thresholdTimer = Timer(remaining, () {
      _thresholdTimer = null;
      _publishCurrent();
      _scheduleThresholdIfNeeded();
    });
  }

  @override
  void dispose() {
    _thresholdTimer?.cancel();
    _thresholdTimer = null;
    super.dispose();
  }
}
