import 'dart:async';

import 'package:flutter_app/features/update_check/application/update_check_service.dart';
import 'package:flutter_app/features/update_check/domain/update_check_models.dart';

/// Scripted [UpdateCheckService] for the T2 controller and widget tests.
class FakeUpdateCheckService implements UpdateCheckService {
  FakeUpdateCheckService({
    List<UpdateDecision>? decisions,
    this.due = false,
    this.installed = '118',
    UpdatePlatform? platform = UpdatePlatform.ios,
  }) : _decisions = decisions ?? <UpdateDecision>[],
       _platform = platform;

  final List<UpdateDecision> _decisions;
  final UpdatePlatform? _platform;
  bool due;
  String installed;
  int checks = 0;
  int dueQueries = 0;
  final List<int> dismissed = <int>[];

  /// When set, [check] waits for it, so a test can interleave a dismissal.
  Completer<void>? gate;

  UpdateDecision _last = const UpdateDecisionNone();

  /// Decisions returned by the following checks, in order. The last one
  /// repeats.
  void queue(UpdateDecision decision) => _decisions.add(decision);

  @override
  bool get isEnabled => true;

  @override
  UpdatePlatform? get platform => _platform;

  @override
  Future<UpdateDecision> check() async {
    checks += 1;
    final wait = gate;
    if (wait != null) await wait.future;
    if (_decisions.isNotEmpty) _last = _decisions.removeAt(0);
    return _last;
  }

  @override
  Future<bool> isCheckDue(DateTime now) async {
    dueQueries += 1;
    return due;
  }

  @override
  Future<void> dismissSoft(int latestBuild) async {
    dismissed.add(latestBuild);
  }

  @override
  Future<String> installedBuildNumber() async => installed;
}
