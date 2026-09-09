import 'package:flutter/foundation.dart';
import '../diagnostics/app_diagnostics.dart';

/// Lightweight startup timing utility.
/// Captures durations between key startup milestones.
/// Only prints in debug mode.
class StartupTiming {
  StartupTiming._();
  static final instance = StartupTiming._();

  final _marks = <String, DateTime>{};

  void mark(String name) {
    _marks[name] = DateTime.now();
    AppDiagnostics.instance.record(
      feature: 'startup',
      stage: 'process',
      outcome: 'ok',
      traceId: AppDiagnostics.instance.supportCode,
      values: {'phase': name, 'durationMs': sinceProcessStartMs() ?? 0},
    );
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

  /// FDC-S1 process-start anchor accessors (observation-only).
  ///
  /// The `app_start` mark is recorded at the first line of `main()`, so it is
  /// the canonical Dart process-start epoch. These let cold-start
  /// instrumentation report `sinceProcessStartMs` (Dart) and thread
  /// `processStartEpochMs` into `node:start` (so Go can do the same on one
  /// shared wall-clock), without inventing a second global anchor.

  /// The wall-clock instant captured at process start (`app_start` mark), or
  /// null if `main()` has not recorded it yet.
  DateTime? get processStart => _marks['app_start'];

  /// The process-start wall-clock epoch in ms, or null if unavailable.
  /// Passed into `node:start` config so Go can compute `sinceProcessStartMs`.
  int? get processStartEpochMs => _marks['app_start']?.millisecondsSinceEpoch;

  /// Elapsed ms from process start to now, or null if the anchor is missing.
  int? sinceProcessStartMs() {
    final start = _marks['app_start'];
    if (start == null) return null;
    return DateTime.now().difference(start).inMilliseconds;
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
