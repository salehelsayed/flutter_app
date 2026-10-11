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

  /// The installed build number, once a check has read it.
  String? get installedBuildNumber => _installedBuildNumber;

  /// The platform whose store page the prompts open, or null when the check
  /// cannot run on this platform.
  UpdatePlatform? get platform => _service.platform;

  /// Runs the launch check once. Later calls do nothing.
  void start() {
    if (_started) return;
    _started = true;
    unawaited(_run());
  }

  Future<void> onResumed() async {
    if (!_started || _disposed) return;
    if (value is UpdateDecisionHard) return _run();
    bool due;
    try {
      due = await _service.isCheckDue(_clock());
    } catch (_) {
      due = false;
    }
    if (due) await _run();
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

  Future<void> _run() async {
    final decision = await _service.check();
    if (decision is UpdateDecisionHard && _installedBuildNumber == null) {
      try {
        _installedBuildNumber = await _service.installedBuildNumber();
      } catch (_) {
        _installedBuildNumber = null;
      }
    }
    if (_disposed) return;
    // A check that started before a dismissal can still return that build.
    if (decision is UpdateDecisionSoft &&
        decision.latestBuild == _dismissedLatestBuild) {
      value = const UpdateDecisionNone();
      return;
    }
    value = decision;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
