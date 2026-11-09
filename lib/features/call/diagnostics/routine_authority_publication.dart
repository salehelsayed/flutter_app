import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

final Object _routineProducerZone = Object();

/// Explicit producer opt-in; this does not affect endpoint/wake publication.
T runWithRoutineAuthorityDiagnostics<T>({
  required bool Function() eligible,
  required T Function() action,
}) => runZoned(action, zoneValues: {_routineProducerZone: eligible});

/// Private, memory-only stream/state identity. None of these keys is exported.
final class RoutineAuthorityPublication {
  RoutineAuthorityPublication._({
    required this.streamKey,
    required this.stateKey,
    required this.routine,
    required bool Function()? eligible,
  }) : _eligible = eligible;

  final Object streamKey;
  final String stateKey;
  final bool routine;
  final Object ticket = Object();
  final bool Function()? _eligible;

  bool get eligibleNow {
    try {
      return _eligible?.call() ?? false;
    } catch (_) {
      return false;
    }
  }

  static RoutineAuthorityPublication? forRequest({
    required Object producer,
    required String command,
    required Map<String, Object?> payload,
    Map<String, Object?>? context,
  }) {
    try {
      final List<String> identityFields;
      switch (command) {
        case 'call_endpoint_set_v1':
          identityFields = ['accountPeerId', 'devicePeerId'];
          if (payload['capabilities'] is! List ||
              payload['deviceKeyEpoch'] is! int ||
              payload['routingHandle'] is! String) {
            return null;
          }
        case 'call_wake_handle_set_v1':
          identityFields = ['authorizedSenderPeerId'];
          if (payload['wakeHandle'] is! String) return null;
        case 'call_token_set_v1':
          identityFields = ['tokenKind'];
          if (payload['token'] is! String || payload['platform'] is! String) {
            return null;
          }
        default:
          return null;
      }
      if (identityFields.any(
        (key) => payload[key] is! String || (payload[key]! as String).isEmpty,
      )) {
        return null;
      }
      final identity = [
        command,
        for (final key in identityFields) payload[key],
      ];
      final state = <String, Object?>{...payload}
        ..remove('diagnostics')
        ..remove('expiresAtMs');
      if (command == 'call_endpoint_set_v1') {
        // The producer advances these freshness fields on every refresh.
        // Device-key epoch, routing handle, capabilities and all other state
        // remain in the fingerprint; native token refreshEpoch is never removed.
        state.remove('preferenceEpoch');
        state.remove('signature');
      }
      final eligible = Zone.current[_routineProducerZone] as bool Function()?;
      return RoutineAuthorityPublication._(
        streamKey: (
          producer,
          sha256.convert(utf8.encode(jsonEncode(identity))).toString(),
        ),
        stateKey: sha256.convert(utf8.encode(jsonEncode(state))).toString(),
        routine:
            // Token responses have further generation checks after _invoke.
            // Keep their observations whole until full success is known.
            command != 'call_token_set_v1' &&
            eligible != null &&
            context?['cause'] == 'resume_refresh' &&
            context?['traceId'] == null,
        eligible: eligible,
      );
    } catch (_) {
      // Unknown shapes preserve ordinary observation and publication behavior.
      return null;
    }
  }
}

/// Coalesces only explicitly qualified, trace-free authority observations.
/// Publication itself never passes through this boundary.
final class RoutineAuthorityPublicationCoalescer {
  RoutineAuthorityPublicationCoalescer({
    required Duration Function() monotonicNow,
    required void Function(Map<String, Object?>) emit,
  }) : _now = monotonicNow,
       _emit = emit;

  static const window = Duration(seconds: 60);
  static const _maxWindows = 128;
  static const _maxPending = 256;
  final Duration Function() _now;
  final void Function(Map<String, Object?>) _emit;
  final Map<Object, _PublicationWindow> _windows = {};
  final Map<Object, _PublicationStart> _pending = {};
  int? _consentEpoch;
  bool _closed = false;

  void add(
    Map<String, Object?> event, {
    required Object streamKey,
    required String stateKey,
    required Object publication,
    required bool routine,
    required bool activeCall,
    required int consentEpoch,
  }) {
    if (_consentEpoch != consentEpoch) {
      reset();
      _consentEpoch = consentEpoch;
    }
    final outcome = event['outcome'];
    final qualified =
        !_closed &&
        routine &&
        !activeCall &&
        !(streamKey is String && streamKey.isEmpty) &&
        stateKey.isNotEmpty &&
        event['source'] == 'flutter' &&
        event['stage'] == 'authority' &&
        event['action'] == 'publish' &&
        (outcome == 'started' || outcome == 'ok') &&
        event['traceId'] == null &&
        (event['role'] == null || event['role'] == 'local') &&
        event['values'] is Map<String, Object?>;
    if (!qualified) {
      final pending = _pending[publication];
      if (pending != null) _finish(pending.window);
      final existing = _windows[streamKey];
      if (existing != null) _finish(existing);
      _emit(event);
      return;
    }

    if (outcome == 'ok') {
      final pending = _pending.remove(publication);
      if (pending == null) {
        // An expired, reset or interrupted invocation must remain observable.
        _emit(event);
        return;
      }
      pending.window.pending.remove(publication);
      pending.window.lastOk = _snapshot(event);
      pending.window.successes++;
      return;
    }

    final duplicate = _pending[publication];
    if (duplicate != null) {
      _finish(duplicate.window);
      _emit(event);
      return;
    }
    var current = _windows[streamKey];
    if (current != null &&
        (current.state != stateKey || _now() >= current.deadline)) {
      _finish(current);
      current = null;
    }
    if (_windows.length >= _maxWindows || _pending.length >= _maxPending) {
      flush();
      current = null;
    }
    if (current == null) {
      current = _PublicationWindow(streamKey, stateKey, _now() + window);
      _windows[streamKey] = current;
      _arm(current);
    }
    final first = !current.startEmitted;
    current.startEmitted = true;
    _pending[publication] = _PublicationStart(
      current,
      _snapshot(event),
      emitted: first,
    );
    current.pending.add(publication);
    if (first) _emit(event);
  }

  void _arm(_PublicationWindow current) {
    final remaining = current.deadline - _now();
    current.timer = Timer(remaining.isNegative ? Duration.zero : remaining, () {
      if (!identical(_windows[current.key], current)) return;
      if (_now() < current.deadline) {
        _arm(current);
      } else {
        _finish(current);
      }
    });
  }

  void _finish(_PublicationWindow current) {
    if (!identical(_windows[current.key], current)) return;
    _windows.remove(current.key);
    current.timer?.cancel();
    final observations = <Map<String, Object?>>[];
    final last = current.lastOk;
    if (last != null) {
      observations.add({
        ...last,
        'values': {
          ...last['values']! as Map<String, Object?>,
          'count': current.successes,
        },
      });
    }
    for (final publication in current.pending) {
      final pending = _pending.remove(publication);
      if (pending != null && !pending.emitted) {
        observations.add(pending.event);
      }
    }
    // Preserve original producer sequence when concurrent invocations complete
    // in a different order. Buffered observations retain their own timestamps.
    observations.sort((a, b) {
      final first = a['sequence'], second = b['sequence'];
      return first is int && second is int ? first.compareTo(second) : 0;
    });
    for (final observation in observations) {
      _emit(observation);
    }
  }

  static Map<String, Object?> _snapshot(Map<String, Object?> event) => {
    ...event,
    'values': {...event['values']! as Map<String, Object?>},
  };

  /// Flushes final successes and any still-unclassified starts without loss.
  void flush() {
    for (final current in _windows.values.toList(growable: false)) {
      _finish(current);
    }
  }

  /// Consent clear/disable discards pending observations, like the archive.
  void reset() {
    for (final current in _windows.values) {
      current.timer?.cancel();
    }
    _windows.clear();
    _pending.clear();
    _consentEpoch = null;
  }

  void close() {
    flush();
    _closed = true;
  }
}

final class _PublicationWindow {
  _PublicationWindow(this.key, this.state, this.deadline);
  final Object key;
  final String state;
  final Duration deadline;
  final Set<Object> pending = {};
  Timer? timer;
  Map<String, Object?>? lastOk;
  int successes = 0;
  bool startEmitted = false;
}

final class _PublicationStart {
  const _PublicationStart(this.window, this.event, {required this.emitted});
  final _PublicationWindow window;
  final Map<String, Object?> event;
  final bool emitted;
}
