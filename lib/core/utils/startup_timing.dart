import 'package:flutter/foundation.dart';

/// Lightweight startup timing utility.
/// Captures durations between key startup milestones.
/// Only prints in debug mode.
class StartupTiming {
  StartupTiming._();
  static final instance = StartupTiming._();

  final _marks = <String, DateTime>{};

  void mark(String name) {
    _marks[name] = DateTime.now();
    if (kDebugMode) {
      final sinceAppStart = _marks['app_start'] != null
          ? DateTime.now().difference(_marks['app_start']!).inMilliseconds
          : 0;
      debugPrint('[STARTUP_TIMING] $name +${sinceAppStart}ms');
    }
  }

  int? elapsed(String from, String to) {
    final start = _marks[from];
    final end = _marks[to];
    if (start == null || end == null) return null;
    return end.difference(start).inMilliseconds;
  }

  void printSummary() {
    if (!kDebugMode) return;
    debugPrint('[STARTUP_TIMING] === Summary ===');
    final appStart = _marks['app_start'];
    if (appStart == null) return;
    for (final entry in _marks.entries) {
      if (entry.key == 'app_start') continue;
      final ms = entry.value.difference(appStart).inMilliseconds;
      debugPrint('[STARTUP_TIMING]   ${entry.key}: +${ms}ms');
    }
  }
}
