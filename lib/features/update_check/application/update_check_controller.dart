import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/update_check_models.dart';
import 'update_check_service.dart';

/// Holds the latest SE-41 update decision for the hard overlay (T2a) and the
/// soft banner (T2b).
///
/// [start] runs the first check. Call it after the first frame and never
/// await it on the startup path. [onResumed] rechecks when a check is due,
/// and on EVERY resume while the decision is hard, so the overlay clears as
/// soon as the version file allows it.
class UpdateCheckController extends ValueNotifier<UpdateDecision> {
  UpdateCheckController({
    required UpdateCheckService service,
    DateTime Function()? clock,
  }) : _service = service,
       _clock = clock ?? DateTime.now,
       super(const UpdateDecisionNone());

  final UpdateCheckService _service;
  final DateTime Function() _clock;

  bool _started = false;
  bool _disposed = false;
  int? _dismissedLatestBuild;
  String? _installedBuildNumber;
  UpdateAvailability _availability = UpdateAvailability.unknown;
  bool _isChecking = false;
  Future<void>? _inFlight;
  bool _forceRequested = false;

  UpdateAvailability get availability => _availability;
  bool get isChecking => _isChecking;

  /// The installed build number, once a check has read it.
  String? get installedBuildNumber => _installedBuildNumber;

  /// The platform whose store page the prompts open, or null when the check
  /// cannot run on this platform.
  UpdatePlatform? get platform => _service.platform;

  /// Runs the launch check once. Later calls do nothing.
  void start() {
    if (_started || _disposed) return;
    unawaited(refresh(force: true));
  }

  Future<void> onResumed() async {
    if (!_started || _disposed) return;
    await refresh(force: value is UpdateDecisionHard);
  }

  /// Settings reuses the current result until due; its refresh action forces
  /// the same shared check used by launch and resume.
  Future<void> refresh({bool force = false}) {
    if (_disposed) return Future<void>.value();
    final running = _inFlight;
    if (running != null) {
      _forceRequested |= force;
      return running;
    }
    final first = !_started;
    _started = true;
    final completion = Completer<void>();
    _inFlight = completion.future;
    unawaited(
      _run(force: force || first).whenComplete(() {
        _inFlight = null;
        _forceRequested = false;
        completion.complete();
      }),
    );
    return completion.future;
  }

  /// Hides the banner for the current latestBuild. A higher latestBuild
  /// shows it again.
  Future<void> dismissSoft() async {
    final soft = value;
    if (soft is! UpdateDecisionSoft) return;
    _dismissedLatestBuild = soft.latestBuild;
    value = const UpdateDecisionNone();
    try {
      await _service.dismissSoft(soft.latestBuild);
    } catch (_) {
      // The banner stays hidden for this launch; a failed save only means it
      // can come back at the next launch.
    }
  }

  Future<void> _run({required bool force}) async {
    if (!force) {
      bool due;
      try {
        due = await _service.isCheckDue(_clock());
      } catch (_) {
        if (!_forceRequested) {
          if (!_disposed) {
            _availability = UpdateAvailability.unknown;
            notifyListeners();
          }
          return;
        }
        due = false;
      }
      if ((!due && !_forceRequested) || _disposed) return;
    }
    _isChecking = true;
    notifyListeners();
    UpdateDecision decision;
    try {
      decision = await _service.check();
      if (decision is UpdateDecisionHard && _installedBuildNumber == null) {
        try {
          _installedBuildNumber = await _service.installedBuildNumber();
        } catch (_) {
          _installedBuildNumber = null;
        }
      }
    } catch (_) {
      if (!_disposed) {
        _isChecking = false;
        _availability = UpdateAvailability.unknown;
        notifyListeners();
      }
      return;
    }
    if (_disposed) return;
    _availability = _service.availability;
    _isChecking = false;
    // A check that started before a dismissal can still return that build.
    final next =
        decision is UpdateDecisionSoft &&
            decision.latestBuild == _dismissedLatestBuild
        ? const UpdateDecisionNone()
        : decision;
    final previous = value;
    value = next;
    if (previous == next) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
