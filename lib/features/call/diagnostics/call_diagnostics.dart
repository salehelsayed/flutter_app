import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../core/bridge/bridge.dart';
import 'call_diagnostic_schema.dart';

typedef CallDiagnosticUpload =
    Future<Set<String>> Function(List<Map<String, Object?>> events);

/// A bounded diagnostic archive. It never participates in call authority.
/// Protocol identities are used only as transient, private binding keys.
final class CallDiagnostics with WidgetsBindingObserver {
  CallDiagnostics._();

  static CallDiagnostics _instance = CallDiagnostics._();
  static CallDiagnostics get instance => _instance;
  static final Object _traceZone = Object();
  static final Object _operationZone = Object();
  static const MethodChannel _channel = MethodChannel(
    'mknoon/call_diagnostics',
  );
  static final RegExp _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  );
  static const int _maxBytes = 4 * 1024 * 1024; // Native gets a separate 1 MiB.
  static const int _maxAttempts = 100;
  static const int _maxEvents = 256;
  static const int _maxAttemptBytes = 64 * 1024;
  static const Duration _retention = Duration(days: 7);

  final ValueNotifier<bool> _enabled = ValueNotifier<bool>(false);
  final List<Map<String, Object?>> _events = [];
  final Set<String> _uploaded = {};
  final Set<String> _uploading = {};
  final Set<String> _resolvingTraces = {};
  final Map<String, int> _eventSizes = {};
  final Map<String, int> _traceDropped = {};
  final Map<String, Map<String, Object?>> _open = {};
  final Set<String> _finished = {};
  final Map<String, String> _calls = {};
  final Map<String, String> _handles = {};
  final Map<String, String> _roles = {};
  // Diagnostic UUIDs only. Late callbacks and native journal entries can still
  // carry the provisional trace after authenticated relay resolution completes.
  final Map<String, String> _traceAliases = {};
  final Map<String, String> _operationReasons = {};
  final Map<String, String> _operationParents = {};
  final Stopwatch _elapsed = Stopwatch();
  final Random _random = Random.secure();
  Directory? _directory;
  Bridge? _bridge;
  Future<bool> Function()? _networkAllowed;
  CallDiagnosticUpload? _testUpload;
  Future<dynamic> Function(String method, Map<String, Object?> data)?
  _testNative;
  DateTime Function() _now = DateTime.now;
  Timer? _timer;
  String _runId = '';
  String _build = 'unknown';
  int _sequence = 0;
  int _consentEpoch = 0;
  bool _consentPending = false;
  bool _clearPending = false;
  bool _nativeConsentPending = false;
  bool _nativeClearPending = false;
  bool _nativeHealthy = true;
  int _dropped = 0;
  int _nativeDroppedSeen = 0;
  int _lastUploadAtMs = 0;
  int _lastConfigureAtMs = 0;
  int _nextUploadAtMs = 0;
  int _uploadFailures = 0;
  bool _native = false;
  bool _disposed = false;
  bool _storageHealthy = true;
  bool _dirty = false;
  bool _flushing = false;
  Completer<void>? _flushDone;
  bool _observing = false;
  Future<void>? _writing;
  String _lastError = 'none';

  bool get enabled => _enabled.value && !_disposed;
  ValueListenable<bool> get enabledListenable => _enabled;
  String? get currentTraceId => _canonicalTrace(Zone.current[_traceZone]);
  String? get currentOperationId => _validId(Zone.current[_operationZone]);

  T runWithTrace<T>(String? traceId, T Function() action) =>
      runZoned(action, zoneValues: {_traceZone: _validId(traceId)});
  T runWithOperation<T>(String? operationId, T Function() action) =>
      runZoned(action, zoneValues: {_operationZone: _validId(operationId)});

  Future<void> initialize({
    required Directory directory,
    Bridge? bridge,
    Future<bool> Function()? networkAllowed,
    String build = 'unknown',
    bool useNative = true,
    bool? enabledOverride,
  }) async {
    if (_disposed) return;
    _bridge = bridge;
    _networkAllowed = networkAllowed;
    if (_directory != null) {
      _lastConfigureAtMs = 0;
      unawaited(flush());
      return;
    }
    _directory = directory;
    _native = useNative && !kIsWeb && (Platform.isIOS || Platform.isAndroid);
    _build = RegExp(r'^[0-9A-Za-z.+_-]{1,80}$').hasMatch(build)
        ? build
        : 'unknown';
    _runId = _newId();
    _elapsed.start();
    try {
      await directory.create(recursive: true);
      final file = _stateFile;
      if (await file.exists()) {
        if (await file.length() > _maxBytes + 1024 * 1024) {
          throw const FormatException('diagnostic quota');
        }
        final raw = jsonDecode(await file.readAsString());
        if (raw is Map && raw['schemaVersion'] == 1) {
          _enabled.value = raw['enabled'] == true;
          _consentEpoch = _boundedInt(raw['consentEpoch']);
          _consentPending = raw['consentPending'] == true;
          _clearPending = raw['clearPending'] == true;
          _nativeClearPending = raw['nativeClearPending'] == true;
          _lastUploadAtMs = _boundedInt(raw['lastUploadAtMs']);
          _dropped = _boundedInt(raw['dropped']);
          _nativeDroppedSeen = _boundedInt(raw['nativeDroppedSeen']);
          if (raw['traceAliases'] case final Map aliases) {
            for (final entry in aliases.entries.take(200)) {
              final from = _validId(entry.key);
              final to = _canonicalTrace(entry.value);
              if (from != null && to != null && from != to) {
                _traceAliases[from] = to;
              }
            }
          }
          if (raw['traceDropped'] case final Map dropped) {
            for (final entry in dropped.entries) {
              final id = _validId(entry.key);
              if (id != null) _traceDropped[id] = _boundedInt(entry.value);
            }
          }
          final records = raw['events'];
          if (records is List) {
            for (final value in records) {
              final event = validateEvent(value);
              if (event != null) _events.add(event);
            }
          }
          for (final event in _events) {
            final trace = _validId(event['traceId']);
            if (trace != null) {
              _roles[trace] = event['role']! as String;
              if (event['stage'] == 'terminal') _finished.add(trace);
            }
          }
          final uploaded = raw['uploaded'];
          if (uploaded is List) _uploaded.addAll(uploaded.whereType<String>());
          final open = raw['open'];
          if (open is Map) {
            for (final entry in open.entries) {
              final id = _validId(entry.key);
              final value = entry.value;
              if (id != null && value is Map) {
                _open[id] = {
                  'role': _closed('role', value['role'], 'local'),
                  'startedAtMs': _boundedInt(value['startedAtMs']),
                };
                _roles[id] = _open[id]!['role']! as String;
              }
            }
          }
        }
      } else {
        // Enable new installs and upgrades without diagnostic state. Existing
        // saved OFF values may be explicit opt-outs and must remain OFF.
        _enabled.value = enabledOverride ?? true;
        _consentPending = enabled;
      }
      if (enabledOverride != null) _enabled.value = enabledOverride;
      if (_consentEpoch == 0) _consentEpoch = _nowMs;
      _prune();
      if (!enabled) {
        _clearMemory();
      } else {
        for (final traceId in List<String>.of(_open.keys)) {
          if (_finished.contains(traceId)) {
            _open.remove(traceId);
            continue;
          }
          record(
            traceId: traceId,
            stage: 'runtime',
            action: 'recover',
            outcome: 'interrupted',
            reason: 'interrupted_before_final_record',
          );
          finishAttempt(
            traceId: traceId,
            outcome: 'interrupted_unknown',
            reason: 'interrupted_before_final_record',
          );
        }
      }
      await _persist();
    } catch (_) {
      _storageHealthy = false;
      _lastError = 'sink_unavailable';
      _enabled.value = false;
      _clearMemory();
    }
    _nativeConsentPending = true;
    await _syncNativeConsent();
    if (useNative) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
      _timer = Timer.periodic(
        const Duration(seconds: 10),
        (_) => unawaited(flush()),
      );
    }
    if (enabled ||
        _consentPending ||
        _nativeConsentPending ||
        _nativeClearPending) {
      unawaited(flush());
    }
  }

  static Future<CallDiagnostics> installForTesting({
    Directory? directory,
    bool? enabled = true,
    DateTime Function()? now,
    CallDiagnosticUpload? upload,
    Bridge? bridge,
    Future<bool> Function()? networkAllowed,
    Future<dynamic> Function(String method, Map<String, Object?> data)? native,
  }) async {
    await _instance.dispose();
    final value = CallDiagnostics._();
    _instance = value;
    if (now != null) value._now = now;
    value._testUpload = upload;
    value._testNative = native;
    await value.initialize(
      directory:
          directory ??
          await Directory.systemTemp.createTemp('call-diagnostics-'),
      useNative: false,
      enabledOverride: enabled,
      bridge: bridge,
      networkAllowed: networkAllowed,
    );
    await value.flush();
    return value;
  }

  String? beginAttempt({String role = 'caller', String source = 'flutter'}) {
    if (!enabled) return null;
    try {
      final id = _newId();
      _roles[id] = _closed('role', role, 'local');
      _open[id] = {'role': _roles[id], 'startedAtMs': _nowMs};
      record(
        traceId: id,
        stage: 'attempt',
        action: 'start',
        outcome: 'started',
      );
      return id;
    } catch (_) {
      _lastError = 'sink_unavailable';
      return null;
    }
  }

  String? beginOperation({
    required String reason,
    String? traceId,
    String? parentOperationId,
  }) {
    if (!enabled) return null;
    try {
      final id = _newId();
      _operationReasons[id] = _closed('reason', reason, 'unknown');
      final parent = parentOperationId ?? currentOperationId;
      if (parent != null) _operationParents[id] = parent;
      if (_operationReasons.length > 200) {
        final first = _operationReasons.keys.first;
        _operationReasons.remove(first);
        _operationParents.remove(first);
      }
      record(
        stage: 'authority',
        action: 'start',
        outcome: 'started',
        reason: reason,
        traceId: traceId,
        operationId: id,
        parentOperationId: parent,
      );
      return id;
    } catch (_) {
      return null;
    }
  }

  void bindCall({
    String? callId,
    String? callHandle,
    required String traceId,
    String role = 'caller',
    bool nativeBinding = false,
  }) {
    final canonical = _canonicalTrace(traceId);
    if (!enabled || canonical == null) return;
    traceId = canonical;
    try {
      final previous = traceForCall(callId: callId, callHandle: callHandle);
      if (previous != null && previous != traceId) _rebind(previous, traceId);
      if (callId != null && callId.isNotEmpty) _calls[callId] = traceId;
      if (callHandle != null && callHandle.isNotEmpty) {
        _handles[callHandle] = traceId;
      }
      _roles[traceId] = _closed('role', role, 'local');
      if (_calls.length > 200) _calls.remove(_calls.keys.first);
      if (_handles.length > 200) _handles.remove(_handles.keys.first);
      if (callHandle != null &&
          callHandle.isNotEmpty &&
          (role == 'caller' || nativeBinding)) {
        unawaited(
          _nativeInvoke('bind', {'callHandle': callHandle, 'traceId': traceId}),
        );
      }
    } catch (_) {
      _lastError = 'sink_unavailable';
    }
  }

  String? traceForCall({String? callId, String? callHandle}) => !enabled
      ? null
      : (callId == null ? null : _calls[callId]) ??
            (callHandle == null ? null : _handles[callHandle]);

  Future<String?> resolveTraceForCall({
    required String callHandle,
    String role = 'callee',
  }) async {
    if (!enabled || callHandle.isEmpty) return null;
    final epoch = _consentEpoch;
    final provisional = traceForCall(callHandle: callHandle);
    final held = <String>{?provisional};
    if (provisional != null) _resolvingTraces.add(provisional);
    try {
      final native = await _nativeInvoke('lookup', {'callHandle': callHandle});
      if (!enabled || epoch != _consentEpoch) return null;
      final known = native is Map && native['version'] == 1
          ? _validId(native['traceId'])
          : null;
      if (known != null) {
        held.add(known);
        _resolvingTraces.add(known);
        bindCall(
          callHandle: callHandle,
          traceId: known,
          role: role,
          nativeBinding: true,
        );
      }
      for (var retry = 0; retry < 3 && enabled; retry++) {
        final response = await _diagnosticRequest('resolve', {
          'callHandle': callHandle,
        });
        if (!enabled || epoch != _consentEpoch) return null;
        final id = _validId(response?['traceId']);
        if (id != null) {
          bindCall(
            callHandle: callHandle,
            traceId: id,
            role: role,
            nativeBinding: true,
          );
          return id;
        }
        if (response?['supported'] == false) break;
        if (retry < 2) {
          await Future<void>.delayed(Duration(milliseconds: 250 * (retry + 1)));
        }
      }
      final id = traceForCall(callHandle: callHandle);
      if (id != null) {
        record(
          traceId: id,
          stage: 'attempt',
          action: 'bind',
          outcome: 'partial_legacy',
          reason: 'legacy_peer',
          values: {'legacy': true},
        );
      }
    } catch (_) {
      _lastError = 'bridge_unavailable';
    } finally {
      _resolvingTraces.removeAll(held);
    }
    return traceForCall(callHandle: callHandle);
  }

  Map<String, Object?>? contextForWire({
    String? callId,
    String? callHandle,
    String? traceId,
    String? operationId,
    String? parentOperationId,
    String reason = 'none',
  }) {
    if (!enabled) return null;
    try {
      final trace =
          _canonicalTrace(traceId) ??
          traceForCall(callId: callId, callHandle: callHandle) ??
          currentTraceId;
      final operation = _validId(operationId) ?? currentOperationId;
      if (trace == null && operation == null) return null;
      return {
        'traceId': ?trace,
        'requestId': _newId(),
        'operationId': ?operation,
        if (_validId(parentOperationId ?? _operationParents[operation])
            case final String id)
          'parentOperationId': id,
        'cause': reason == 'none' && operation != null
            ? (_operationReasons[operation] ?? 'none')
            : _closed('reason', reason, 'unknown'),
      };
    } catch (_) {
      return null;
    }
  }

  void record({
    required String stage,
    required String action,
    required String outcome,
    String reason = 'none',
    String? traceId,
    String? operationId,
    String? parentOperationId,
    String? requestId,
    Map<String, Object?> values = const {},
  }) {
    if (!enabled) return;
    try {
      final trace = _canonicalTrace(traceId) ?? currentTraceId;
      final operation = _validId(operationId) ?? currentOperationId;
      final event = <String, Object?>{
        'schemaVersion': 1,
        'eventId': _newId(),
        'source': 'flutter',
        'role': trace == null ? 'local' : (_roles[trace] ?? 'local'),
        'runId': _runId,
        'sequence': ++_sequence,
        'occurredAtMs': _nowMs,
        'elapsedMs': _elapsed.elapsedMilliseconds,
        'stage': _closed('stage', stage, 'runtime'),
        'action': _closed('action', action, 'snapshot'),
        'outcome': _closed('outcome', outcome, 'unknown'),
        'reason': _closed('reason', reason, 'unknown'),
        'values': _safeValues(values),
        'build': _build,
        'traceId': ?trace,
        'operationId': ?operation,
        if (_validId(parentOperationId) case final String id)
          'parentOperationId': id,
        if (_validId(requestId) case final String id) 'requestId': id,
      };
      _append(event);
    } catch (_) {
      _lastError = 'sink_unavailable';
    }
  }

  void finishAttempt({
    String? traceId,
    required String outcome,
    String reason = 'none',
    Map<String, Object?> values = const {},
  }) {
    final id = _canonicalTrace(traceId) ?? currentTraceId;
    if (!enabled || id == null || !_finished.add(id)) return;
    record(
      traceId: id,
      stage: 'terminal',
      action: 'finish',
      outcome: outcome,
      reason: reason,
      values: {
        ...values,
        'terminal': true,
        if ((_traceDropped[id] ?? 0) > 0) ...{
          'truncated': true,
          'dropped': _traceDropped[id],
          'completeness': 'truncated',
        },
      },
    );
    _open.remove(id);
    _schedulePersist();
    if (_testUpload == null) unawaited(flush());
  }

  Future<void> setEnabled(bool value) async {
    if (_disposed || _directory == null) return;
    if (value == enabled) return;
    _consentEpoch = max(_consentEpoch + 1, _nowMs);
    _consentPending = true;
    _nativeConsentPending = true;
    if (!value) _nativeClearPending = true;
    _enabled.value = value;
    if (!value) _clearMemory();
    await _persist();
    if (!_storageHealthy && value) _enabled.value = false;
    await _syncNativeConsent();
    _lastConfigureAtMs = 0;
    await _syncConsent();
    if (enabled) {
      record(
        stage: 'runtime',
        action: 'enable',
        outcome: 'ok',
        reason: 'user_action',
      );
      unawaited(flush());
    }
  }

  Future<void> clear() async {
    _consentEpoch = max(_consentEpoch + 1, _nowMs);
    _consentPending = true;
    _clearPending = true;
    _nativeConsentPending = true;
    _nativeClearPending = true;
    _clearMemory();
    await _persist();
    await _syncNativeConsent();
    await _syncConsent();
  }

  Future<Map<String, Object?>> status() async => {
    'enabled': enabled,
    'retainedEvents': _events.length,
    'queuedEvents': _events
        .where((e) => !_uploaded.contains(e['eventId']))
        .length,
    'droppedEvents': _dropped,
    'storageHealthy': _storageHealthy && _nativeHealthy,
    'nativeStorageHealthy': _nativeHealthy,
    'consentPending':
        _consentPending ||
        _nativeConsentPending ||
        _nativeClearPending ||
        _clearPending,
    'lastUploadAtMs': _lastUploadAtMs,
    'lastError': _lastError,
    'traceCodes': _events
        .map((e) => e['traceId'])
        .whereType<String>()
        .toSet()
        .toList(),
  };

  Future<String> exportPreview() async {
    await _persist();
    return const JsonEncoder.withIndent('  ').convert({
      'schemaVersion': 1,
      'exportedAtMs': _nowMs,
      'retentionDays': 7,
      'droppedEvents': _dropped,
      'events': _events,
    });
  }

  Future<List<Map<String, Object?>>> eventsForTesting() async {
    await _persist();
    return _events.map((e) => Map<String, Object?>.from(e)).toList();
  }

  Future<void> flush() async {
    if (_flushing) {
      await _flushDone?.future;
      return;
    }
    if (!enabled &&
        !_consentPending &&
        !_nativeConsentPending &&
        !_nativeClearPending) {
      return;
    }
    _flushing = true;
    _flushDone = Completer<void>();
    try {
      if (_nativeConsentPending || _nativeClearPending) {
        await _syncNativeConsent();
      }
      if (!enabled) {
        await _syncConsent();
        return;
      }
      final epoch = _consentEpoch;
      await _drainNative();
      _prune();
      await _persist();
      if (!enabled || !_storageHealthy || _nowMs < _nextUploadAtMs) return;
      if (_testUpload == null) {
        if (_bridge?.isInitialized != true) return;
        if (_consentPending ||
            _lastConfigureAtMs == 0 ||
            _nowMs - _lastConfigureAtMs > 5 * 60 * 1000) {
          if (!await _syncConsent()) {
            _uploadFailed('legacy_peer');
            return;
          }
          _lastConfigureAtMs = _nowMs;
        }
      }
      if (!enabled || epoch != _consentEpoch) return;
      final batch = _pendingUploadBatch();
      if (batch.isEmpty) return;
      _uploading.addAll(batch.map((e) => e['eventId']! as String));
      final Set<String> accepted;
      var acknowledged = 0;
      if (_testUpload != null) {
        accepted = await _testUpload!(batch);
      } else {
        final result = await _diagnosticRequest('upload', {
          'events': batch,
        }, expectedEpoch: epoch);
        if (!enabled || epoch != _consentEpoch) return;
        if (result == null || result['supported'] != true) {
          _uploadFailed('bridge_unavailable');
          return;
        }
        accepted = (result['acceptedEventIds'] as List? ?? [])
            .whereType<String>()
            .toSet();
        // Explicit schema rejections are terminal for these telemetry records.
        final rejected = (result['rejectedEventIds'] as List? ?? [])
            .whereType<String>()
            .toSet();
        for (final event in batch) {
          if (rejected.contains(event['eventId'])) {
            if (_uploaded.add(event['eventId']! as String)) {
              acknowledged++;
              _dropped++;
            }
          }
        }
      }
      if (!enabled || epoch != _consentEpoch) return;
      for (final event in batch) {
        if (accepted.contains(event['eventId'])) {
          if (_uploaded.add(event['eventId']! as String)) acknowledged++;
        }
      }
      if (acknowledged == 0) {
        _uploadFailed('bridge_unavailable');
      } else {
        _lastUploadAtMs = _nowMs;
        _uploadFailures = 0;
        _nextUploadAtMs = 0;
        _lastError = 'none';
      }
      await _persist();
    } catch (_) {
      _uploadFailed('sink_unavailable');
    } finally {
      _uploading.clear();
      _flushing = false;
      _flushDone?.complete();
      _flushDone = null;
    }
  }

  List<Map<String, Object?>> _pendingUploadBatch() {
    final terminal = <Map<String, Object?>>[];
    final verifiedMedia = <Map<String, Object?>>[];
    final ordinary = <Map<String, Object?>>[];
    final mediaSeen = <String>{};
    for (final event in _events) {
      final trace = event['traceId'];
      final firstMedia =
          trace is String &&
          event['stage'] == 'media' &&
          event['outcome'] == 'media_flow_verified' &&
          mediaSeen.add(trace);
      if (_uploaded.contains(event['eventId']) ||
          _resolvingTraces.contains(trace)) {
        continue;
      }
      if (event['stage'] == 'terminal') {
        terminal.add(event);
      } else if (firstMedia) {
        verifiedMedia.add(event);
      } else {
        ordinary.add(event);
      }
    }
    return [
      ...terminal,
      ...verifiedMedia,
      ...ordinary,
    ].take(64).map((e) => Map<String, Object?>.from(e)).toList();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _nextUploadAtMs = 0;
      unawaited(flush());
    } else {
      _schedulePersist();
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _timer?.cancel();
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    await _persist();
    _disposed = true;
  }

  void _append(Map<String, Object?> event) {
    final canonical = _canonicalTrace(event['traceId']);
    if (canonical != null && canonical != event['traceId']) {
      event['traceId'] = canonical;
      event['role'] = _roles[canonical] ?? event['role'];
      _eventSizes.remove(event['eventId']);
    }
    if (canonical != null &&
        (event['source'] == 'ios' || event['source'] == 'android') &&
        (_roles[canonical] == 'caller' || _roles[canonical] == 'callee')) {
      event['role'] = _roles[canonical];
      _eventSizes.remove(event['eventId']);
    }
    final trace = event['traceId'];
    final group = _events
        .where((e) => trace != null && e['traceId'] == trace)
        .toList();
    final terminal = event['stage'] == 'terminal';
    if (!terminal &&
        (group.length >= _maxEvents ||
            group.fold<int>(0, (n, e) => n + _eventSize(e)) +
                    _eventSize(event) >
                _maxAttemptBytes)) {
      _dropped++;
      if (trace is String) {
        _traceDropped[trace] = (_traceDropped[trace] ?? 0) + 1;
      }
      _eventSizes.remove(event['eventId']);
      _schedulePersist();
      return;
    }
    if (terminal) {
      // Reserve room for the terminal summary even when stage events hit quota.
      var groupBytes = group.fold<int>(0, (n, e) => n + _eventSize(e));
      final eventBytes = _eventSize(event);
      while ((group.length >= _maxEvents ||
              groupBytes + eventBytes + 256 > _maxAttemptBytes) &&
          group.isNotEmpty) {
        final removed = group.removeAt(0);
        groupBytes -= _eventSize(removed);
        _events.remove(removed);
        _uploaded.remove(removed['eventId']);
        _dropped++;
        if (trace is String) {
          _traceDropped[trace] = (_traceDropped[trace] ?? 0) + 1;
        }
      }
      if (trace is String && (_traceDropped[trace] ?? 0) > 0) {
        event['values'] = {
          ...event['values'] as Map,
          'truncated': true,
          'dropped': _traceDropped[trace],
          'completeness': 'truncated',
        };
        _eventSizes.remove(event['eventId']);
      }
    }
    _events.add(event);
    _prune();
    _schedulePersist();
  }

  void _rebind(String from, String to) {
    _traceAliases.updateAll((_, id) => id == from ? to : id);
    _traceAliases[from] = to;
    if (_traceAliases.length > 200) {
      _traceAliases.remove(_traceAliases.keys.first);
    }
    for (final event in _events) {
      if (event['traceId'] == from &&
          !_uploaded.contains(event['eventId']) &&
          !_uploading.contains(event['eventId'])) {
        event['traceId'] = to;
      }
    }
    final open = _open.remove(from);
    final dropped = _traceDropped.remove(from);
    if (dropped != null) _traceDropped[to] = (_traceDropped[to] ?? 0) + dropped;
    if (_finished.remove(from)) _finished.add(to);
    if (open != null && !_finished.contains(to)) {
      _open.putIfAbsent(to, () => open);
    }
    _roles.remove(from);
    _calls.updateAll((_, id) => id == from ? to : id);
    _handles.updateAll((_, id) => id == from ? to : id);
    _schedulePersist();
  }

  void _prune() {
    final cutoff = _nowMs - _retention.inMilliseconds;
    _events.removeWhere((e) => (e['occurredAtMs'] as int) < cutoff);
    final traceOrder = <String>{};
    for (final e in _events) {
      if (e['traceId'] case final String id) traceOrder.add(id);
    }
    while (traceOrder.length > _maxAttempts) {
      final first = traceOrder.first;
      traceOrder.remove(first);
      _dropped += _events.where((e) => e['traceId'] == first).length;
      _events.removeWhere((e) => e['traceId'] == first);
      _open.remove(first);
      _roles.remove(first);
      _finished.remove(first);
      _calls.removeWhere((_, id) => id == first);
      _handles.removeWhere((_, id) => id == first);
    }
    var bytes = _events.fold<int>(0, (n, e) => n + _eventSize(e));
    while (bytes > _maxBytes - 128 * 1024 && _events.isNotEmpty) {
      bytes -= _eventSize(_events.removeAt(0));
      _dropped++;
    }
    final ids = _events.map((e) => e['eventId']).toSet();
    _eventSizes.removeWhere((id, _) => !ids.contains(id));
    _uploaded.removeWhere((id) => !ids.contains(id));
    _open.removeWhere((_, e) => (e['startedAtMs'] as int) < cutoff);
    final retained =
        _events.map((e) => e['traceId']).whereType<String>().toSet()
          ..addAll(_open.keys);
    _roles.removeWhere((id, _) => !retained.contains(id));
    _finished.removeWhere((id) => !retained.contains(id));
    _traceDropped.removeWhere((id, _) => !retained.contains(id));
    _traceAliases.removeWhere((_, id) => !retained.contains(id));
  }

  void _clearMemory() {
    _events.clear();
    _uploaded.clear();
    _eventSizes.clear();
    _traceDropped.clear();
    _resolvingTraces.clear();
    _open.clear();
    _finished.clear();
    _calls.clear();
    _handles.clear();
    _roles.clear();
    _traceAliases.clear();
    _operationReasons.clear();
    _operationParents.clear();
    _dropped = 0;
    _nativeDroppedSeen = 0;
  }

  void _uploadFailed(String reason) {
    _lastError = reason;
    _uploadFailures = min(_uploadFailures + 1, 6);
    _nextUploadAtMs = _nowMs + min(300000, 5000 * (1 << _uploadFailures));
  }

  String? _canonicalTrace(Object? value) {
    var id = _validId(value);
    for (var depth = 0; id != null && depth <= 200; depth++) {
      final next = _traceAliases[id];
      if (next == null) return id;
      id = next;
    }
    return null;
  }

  int _eventSize(Map<String, Object?> event) => _eventSizes.putIfAbsent(
    event['eventId']! as String,
    () => utf8.encode(jsonEncode(event)).length,
  );

  Future<Map<String, dynamic>?> _diagnosticRequest(
    String op,
    Map<String, Object?> data, {
    int? expectedEpoch,
  }) async {
    final bridge = _bridge;
    if (bridge?.isInitialized != true) return null;
    try {
      if (_networkAllowed != null && !await _networkAllowed!()) return null;
      if (expectedEpoch != null && expectedEpoch != _consentEpoch) return null;
      if (op != 'configure' && op != 'clear' && !enabled) return null;
      final result = jsonDecode(
        await bridge!
            .send(
              jsonEncode({
                'cmd': 'call_diagnostics_v1',
                'payload': {
                  'op': op,
                  ...data,
                  if (op == 'configure') 'enabled': enabled,
                  if (op == 'configure') 'pushTrace': enabled,
                  'consentEpoch': _consentEpoch,
                },
              }),
            )
            .timeout(const Duration(seconds: 5)),
      );
      if (result is! Map) return null;
      final value = result['data'];
      if (result['ok'] == true && value is Map) {
        return Map<String, dynamic>.from(value);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _syncConsent() async {
    final epoch = _consentEpoch;
    if (_clearPending) {
      final cleared = await _diagnosticRequest(
        'clear',
        {},
        expectedEpoch: epoch,
      );
      if (epoch != _consentEpoch ||
          cleared?['supported'] != true ||
          cleared?['reason'] != null) {
        return false;
      }
      _clearPending = false;
      await _persist();
    }
    final configured = await _diagnosticRequest('configure', {});
    if (epoch != _consentEpoch ||
        configured?['supported'] != true ||
        configured?['reason'] != null ||
        configured?['enabled'] != enabled) {
      return false;
    }
    _consentPending = false;
    _lastConfigureAtMs = _nowMs;
    await _persist();
    return true;
  }

  Future<void> _syncNativeConsent() async {
    final epoch = _consentEpoch;
    if (!_native && _testNative == null) {
      _nativeConsentPending = false;
      _nativeClearPending = false;
      return;
    }
    final configured = await _nativeInvoke('configure', {'enabled': enabled});
    if (epoch != _consentEpoch) return;
    _nativeConsentPending = configured != true;
    if (_nativeClearPending) {
      final cleared = await _nativeInvoke('clear', {});
      if (epoch != _consentEpoch) return;
      _nativeClearPending = cleared != true;
    }
    _nativeHealthy = !_nativeConsentPending && !_nativeClearPending;
    if (!_nativeHealthy) _lastError = 'native_persistence_failed';
    if (_nativeHealthy && _lastError == 'native_persistence_failed') {
      _lastError = 'none';
    }
    await _persist();
  }

  Future<dynamic> _nativeInvoke(
    String method,
    Map<String, Object?> data,
  ) async {
    if (!_native && _testNative == null) return null;
    try {
      if (_testNative != null) {
        return await _testNative!(method, {
          'version': 1,
          ...data,
          'consentEpoch': _consentEpoch,
        });
      }
      return await _channel
          .invokeMethod<dynamic>(method, {
            'version': 1,
            ...data,
            'consentEpoch': _consentEpoch,
          })
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      return null;
    }
  }

  Future<void> _drainNative() async {
    if (!enabled) return;
    final epoch = _consentEpoch;
    final result = await _nativeInvoke('drain', {'limit': 64});
    if (!enabled || epoch != _consentEpoch) return;
    if (result is! Map || result['version'] != 1 || result['events'] is! List) {
      return;
    }
    final nativeDropped = _boundedInt(result['droppedEvents']);
    final newlyDropped = max(0, nativeDropped - _nativeDroppedSeen);
    _dropped += newlyDropped;
    _nativeDroppedSeen = nativeDropped;
    if (newlyDropped > 0) {
      record(
        stage: 'runtime',
        action: 'drop',
        outcome: 'partial',
        reason: 'quota_exceeded',
        values: {'dropped': newlyDropped, 'truncated': true},
      );
    }
    final existing = _events.map((e) => e['eventId']).toSet();
    final ack = <String>[];
    for (final raw in (result['events'] as List).take(64)) {
      final event = validateEvent(raw);
      if (event == null ||
          (event['source'] != 'ios' && event['source'] != 'android')) {
        _dropped++;
        if (raw is Map) {
          final id = _validId(raw['eventId']);
          if (id != null) ack.add(id);
        }
        continue;
      }
      final id = event['eventId']! as String;
      if (existing.add(id)) _append(event);
      ack.add(id);
    }
    await _persist();
    if (enabled &&
        epoch == _consentEpoch &&
        _storageHealthy &&
        ack.isNotEmpty) {
      await _nativeInvoke('ack', {'eventIds': ack});
    }
  }

  File get _stateFile => File('${_directory!.path}/state.json');
  int get _nowMs => _now().toUtc().millisecondsSinceEpoch;

  void _schedulePersist() {
    if (_directory != null && !_disposed) unawaited(_persist());
  }

  Future<void> _persist() {
    if (_directory == null || _disposed) return Future<void>.value();
    _dirty = true;
    if (_writing != null) return _writing!;
    final completer = Completer<void>();
    _writing = completer.future;
    unawaited(() async {
      try {
        while (_dirty) {
          _dirty = false;
          final text = jsonEncode({
            'schemaVersion': 1,
            'enabled': _enabled.value,
            'consentEpoch': _consentEpoch,
            'consentPending': _consentPending,
            'clearPending': _clearPending,
            'nativeClearPending': _nativeClearPending,
            'lastUploadAtMs': _lastUploadAtMs,
            'dropped': _dropped,
            'nativeDroppedSeen': _nativeDroppedSeen,
            'traceDropped': _traceDropped,
            'traceAliases': _traceAliases,
            'events': _events,
            'uploaded': _uploaded.toList(),
            'open': _open,
          });
          final temporary = File('${_stateFile.path}.new');
          await temporary.writeAsString(text, flush: true);
          await temporary.rename(_stateFile.path);
          _storageHealthy = true;
        }
      } catch (_) {
        _storageHealthy = false;
        _lastError = 'sink_unavailable';
      } finally {
        _writing = null;
        completer.complete();
      }
    }());
    return completer.future;
  }

  String _newId() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  static String? _validId(Object? value) =>
      value is String && _uuid.hasMatch(value) ? value.toLowerCase() : null;
  static int _boundedInt(Object? value) =>
      value is int && value >= 0 && value <= 9007199254740991 ? value : 0;
  static String _snake(String value) => value.replaceAllMapped(
    RegExp(r'[A-Z]'),
    (m) => '_${m[0]!.toLowerCase()}',
  );
  static String _closed(String field, Object? value, String fallback) {
    if (value is! String) return fallback;
    final normalized = _snake(value);
    return (callDiagnosticSchemaV1[field] as List).contains(normalized)
        ? normalized
        : fallback;
  }

  static Map<String, Object?> _safeValues(Map values) {
    final result = <String, Object?>{};
    final enums = callDiagnosticSchemaV1['enumValues'] as Map;
    for (final entry in values.entries) {
      final key = entry.key, value = entry.value;
      if ((callDiagnosticSchemaV1['booleanValues'] as List).contains(key) &&
          value is bool) {
        result[key as String] = value;
      }
      if ((callDiagnosticSchemaV1['integerValues'] as List).contains(key) &&
          value is int &&
          value >= 0 &&
          value <= 9007199254740991) {
        result[key as String] = value;
      }
      if (enums[key] is List &&
          value is String &&
          (enums[key] as List).contains(_snake(value))) {
        result[key as String] = _snake(value);
      }
    }
    return result;
  }

  /// Rejects whole foreign records rather than laundering arbitrary strings.
  static Map<String, Object?>? validateEvent(Object? raw) {
    if (raw is! Map || raw['schemaVersion'] != 1) return null;
    try {
      final keys = {
        ...callDiagnosticSchemaV1['required'] as List,
        ...callDiagnosticSchemaV1['optional'] as List,
      };
      if (raw.keys.any((k) => k is! String || !keys.contains(k))) return null;
      for (final key in callDiagnosticSchemaV1['required'] as List) {
        if (!raw.containsKey(key)) return null;
      }
      for (final key in callDiagnosticSchemaV1['uuidFields'] as List) {
        if (raw.containsKey(key) && _validId(raw[key]) == null) return null;
      }
      for (final key in [
        'source',
        'role',
        'stage',
        'action',
        'outcome',
        'reason',
      ]) {
        if (!(callDiagnosticSchemaV1[key] as List).contains(raw[key])) {
          return null;
        }
      }
      for (final key in ['sequence', 'occurredAtMs', 'elapsedMs']) {
        if (raw[key] is! int || _boundedInt(raw[key]) != raw[key]) return null;
      }
      if (raw['values'] is! Map) return null;
      final safe = _safeValues(raw['values'] as Map);
      if (jsonEncode(safe) != jsonEncode(raw['values'])) return null;
      if (raw.containsKey('build') &&
          (raw['build'] is! String ||
              !RegExp(
                r'^[0-9A-Za-z.+_-]{1,80}$',
              ).hasMatch(raw['build'] as String))) {
        return null;
      }
      if (utf8.encode(jsonEncode(raw)).length > 4096) return null;
      return Map<String, Object?>.from(raw);
    } catch (_) {
      return null;
    }
  }
}
