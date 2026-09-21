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
    this.retryInProgress = false,
  });

  const PushRegistrationHealthViewModel.neutral()
    : phase = null,
      reason = PushRegistrationHealthReason.none,
      warningVisible = false,
      action = PushRegistrationHealthAction.none,
      retryInProgress = false;

  final PushRegistrationHealthPhase? phase;
  final PushRegistrationHealthReason reason;
  final bool warningVisible;
  final PushRegistrationHealthAction action;
  final bool retryInProgress;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is PushRegistrationHealthViewModel &&
            other.phase == phase &&
            other.reason == reason &&
            other.warningVisible == warningVisible &&
            other.action == action &&
            other.retryInProgress == retryInProgress;
  }

  @override
  int get hashCode =>
      Object.hash(phase, reason, warningVisible, action, retryInProgress);
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
  Completer<void>? _retry;
  bool _disposed = false;

  PushRegistrationHealthRecord? get record => _record;

  void publish(PushRegistrationHealthRecord record) {
    _record = record;
    _thresholdTimer?.cancel();
    _thresholdTimer = null;
    _publishCurrent();
    _scheduleThresholdIfNeeded();
  }

  /// Owns the app-shell retry until the real coordinator future settles.
  /// Repeated activations join the same operation, including before a rebuild.
  Future<void> retryRegistration(Future<void> Function() operation) {
    if (_disposed) return Future<void>.value();
    final pending = _retry;
    if (pending != null) return pending.future;
    if (value.action != PushRegistrationHealthAction.retry) {
      return Future<void>.value();
    }
    final retry = Completer<void>();
    _retry = retry;
    _publishCurrent();
    Future<void>.sync(operation).then(
      (_) {
        _settleRetry(retry);
        retry.complete();
      },
      onError: (Object error, StackTrace stack) {
        _settleRetry(retry);
        retry.completeError(error, stack);
      },
    );
    return retry.future;
  }

  void _settleRetry(Completer<void> retry) {
    if (_disposed || !identical(_retry, retry)) return;
    _retry = null;
    _publishCurrent();
  }

  void clear() {
    _retry = null;
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
      retryInProgress: _retry != null,
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
    _disposed = true;
    _retry = null;
    _thresholdTimer?.cancel();
    _thresholdTimer = null;
    super.dispose();
  }
}
