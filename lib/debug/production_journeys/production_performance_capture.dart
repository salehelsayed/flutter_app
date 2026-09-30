import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

/// Installed before production starts its node, after invocation admission.
/// Event totalMs values retain their production-defined timing intervals.
/// The monotonic observation clock starts here, not at OS/Dart application entry.
final class ProductionPerformanceCapture with WidgetsBindingObserver {
  ProductionPerformanceCapture() {
    _lease = installScopedE2EFlowEventSink((event) {
      if (_events.contains(event['event'])) _record(event);
    });
    WidgetsBinding.instance.addObserver(this);
    _expiry = Timer(const Duration(minutes: 20), () {
      _expired = true;
      dispose();
    });
  }

  static const _events = {
    'P2P_SERVICE_START_NODE_BEGIN',
    'P2P_SERVICE_START_NODE_CORE_BEGIN',
    'P2P_SERVICE_START_NODE_CORE_ALREADY_RUNNING',
    'TIME_TO_ONLINE_BADGE',
    'TIME_TO_SENDABLE_BADGE',
    'TIME_TO_RELAY_READY_BADGE',
    'TIME_TO_ONLINE_BADGE_WIDGET',
    'FIRST_SEND_SUCCESS_IN_WINDOW',
    'FIRST_INBOX_SUCCESS_IN_WINDOW',
    'RELAY_RECOVERY_START',
    'RELAY_OUTAGE_TIMING',
    'APP_LIFECYCLE_RESUME_COMPLETE',
    'node:startup_timing',
    'circuit_address:timing',
  };
  final _clock = Stopwatch()..start();
  final _observations = <Map<String, Object?>>[];
  late final E2EFlowEventSinkLease _lease;
  Timer? _expiry;
  bool _overflow = false, _disposed = false, _expired = false;
  Map<String, Object?> Function()? _pausedObserver;
  Map<String, Object?>? _pausedSnapshot;

  /// Bind the existing production state reader. Capture at the lifecycle
  /// callback so a short Home/resume flow needs no host polling delay.
  void bindPausedObserver(Map<String, Object?> Function() observer) {
    if (_disposed || _pausedObserver != null) {
      throw StateError('paused observation already bound or disposed');
    }
    _pausedObserver = observer;
  }

  void clearPausedSnapshot() => _pausedSnapshot = null;

  Map<String, Object?> pausedSnapshot() {
    snapshot(); // Retain expiry, disposal and overflow rejection.
    final paused = _pausedSnapshot;
    if (paused == null) throw StateError('actual paused observation missing');
    return Map<String, Object?>.from(jsonDecode(jsonEncode(paused)) as Map);
  }

  void _record(Map<String, Object?> event) {
    if (_disposed) return;
    if (_observations.length >= 1024) {
      _overflow = true;
      return;
    }
    _observations.add({
      ...Map<String, Object?>.from(jsonDecode(jsonEncode(event)) as Map),
      'sequence': _observations.length + 1,
      'observedMicros': _clock.elapsedMicroseconds,
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _record({
      'event': 'APPLICATION_LIFECYCLE',
      'details': {'state': state.name},
    });
    if (!_disposed && !_overflow && state == AppLifecycleState.paused) {
      final observed = _pausedObserver?.call();
      _pausedSnapshot = observed == null
          ? null
          : Map<String, Object?>.from(jsonDecode(jsonEncode(observed)) as Map);
    }
  }

  Map<String, Object?> snapshot() {
    if (_overflow || _expired || _disposed) {
      throw StateError('performance observation unavailable');
    }
    return {
      'processId': pid,
      'captureStartedBeforeRuntime': true,
      'timingScope': 'production node readiness and actual OS lifecycle',
      'lifecycle': WidgetsBinding.instance.lifecycleState?.name,
      'observedMicros': _clock.elapsedMicroseconds,
      'events': jsonDecode(jsonEncode(_observations)),
    };
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _expiry?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _lease.release();
    _pausedObserver = null;
    _pausedSnapshot = null;
    _clock.stop();
  }
}
