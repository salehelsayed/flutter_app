import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../core/bridge/bridge.dart';
import '../../../core/diagnostics/diagnostic_archive_writer.dart';
import 'call_diagnostic_schema.dart';

typedef CallDiagnosticUpload =
    Future<Set<String>> Function(List<Map<String, Object?>> events);

typedef CallDiagnosticPersist =
    Future<void> Function(String path, Map<String, Object?> state);

final _callDiagnosticJsonBytes = DiagnosticJsonByteCounter(
  cachedStrings: [
    for (final options in CallDiagnostics._schemaSets.values) ...options,
    for (final entry in CallDiagnostics._enumValues.entries) ...[
      entry.key,
      ...entry.value,
    ],
  ],
);

Future<String> _encodeCallDiagnosticPreview(Map<String, Object?> state) =>
    Isolate.run(() => const JsonEncoder.withIndent('  ').convert(state));

Future<String> _readCallDiagnosticPreview(
  String path,
  Map<String, Object?> header,
) => Isolate.run(() async {
  final raw = jsonDecode(await File(path).readAsString());
  if (raw is! Map || raw['schemaVersion'] != 1 || raw['events'] is! List) {
    throw const FormatException('diagnostic state');
  }
  // Storage-only metadata is deliberately excluded from the support export.
  final events = (raw['events'] as List)
      .map(CallDiagnostics.validateEvent)
      .whereType<Map<String, Object?>>()
      .toList();
  return const JsonEncoder.withIndent(
    '  ',
  ).convert({...header, 'events': events});
});

Future<dynamic> _readCallDiagnosticState(String path) => Isolate.run(() async {
  final raw = jsonDecode(await File(path).readAsString());
  if (raw is Map && raw['events'] is List) {
    final events = (raw['events'] as List)
        .map(CallDiagnostics.validateEvent)
        .whereType<Map<String, Object?>>()
        .toList();
    raw['events'] = events;
    raw['_loadedEventSizes'] = <String, int>{
      for (final event in events)
        event['eventId']! as String: _callDiagnosticJsonBytes.count(event),
    };
  }
  return raw;
});

final class _CallDiagnosticGroup {
  final events = SplayTreeMap<int, Map<String, Object?>>();
  int bytes = 0;
}

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
  static final _buildPattern = RegExp(r'^[0-9A-Za-z.+_-]{1,80}$');
  static final _uppercase = RegExp(r'[A-Z]');
  static final Map<String, Set<String>> _schemaSets = {
    for (final entry in callDiagnosticSchemaV1.entries)
      if (entry.value is List) entry.key: Set<String>.from(entry.value as List),
  };
  static final Map<String, Set<String>> _enumValues = {
    for (final entry
        in (callDiagnosticSchemaV1['enumValues'] as Map<String, dynamic>)
            .entries)
      entry.key: Set<String>.from(entry.value as List),
  };
  static final _eventKeys = {
    ..._schemaSets['required']!,
    ..._schemaSets['optional']!,
  };
  static const int _maxBytes = 4 * 1024 * 1024; // Native gets a separate 1 MiB.
  static const int _maxAttempts = 100;
  static const int _maxEvents = 256;
  static const int _maxAttemptBytes = 64 * 1024;
  static const Duration _retention = Duration(days: 7);

  final ValueNotifier<bool> _enabled = ValueNotifier<bool>(false);
  final Map<String, Map<String, Object?>> _eventsById = {};
  Iterable<Map<String, Object?>> get _events => _eventsById.values;
  final Map<String, _CallDiagnosticGroup> _groups = {};
  final Map<String, int> _eventOrder = {};
  int _nextEventOrder = 0;
  int _retainedBytes = 0;
  int? _nextExpiryMs;
  final Set<String> _uploaded = {};
  Set<String> _uploadedAdditions = {};
  Set<String> _uploadedRemovals = {};
  bool _fullMetadataRequired = true;
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
  DiagnosticArchiveWriter? _archiveWriter;
  bool _ready = false;
  Bridge? _bridge;
  Future<bool> Function()? _networkAllowed;
  CallDiagnosticUpload? _testUpload;
  CallDiagnosticPersist? _testPersist;
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
  bool _urgentWriteRequested = false;
  Timer? _persistTimer;
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
    if (_testPersist == null) {
      _archiveWriter = DiagnosticArchiveWriter(
        _stateFile.path,
        validateEvent: CallDiagnostics.validateEvent,
      );
    }
    _native = useNative && !kIsWeb && (Platform.isIOS || Platform.isAndroid);
    _build = _buildPattern.hasMatch(build) ? build : 'unknown';
    _runId = _newId();
    _elapsed.start();
    try {
      await directory.create(recursive: true);
      final file = _stateFile;
      if (await file.exists()) {
        if (await file.length() > _maxBytes + 1024 * 1024) {
          throw const FormatException('diagnostic quota');
        }
        final raw = await _readCallDiagnosticState(file.path);
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
            _eventSizes.addAll(
              Map<String, int>.from(raw['_loadedEventSizes'] as Map),
            );
            for (final value in records) {
              _indexEvent(value as Map<String, Object?>);
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
      _prune(force: true);
      if (!enabled) {
        _clearMemory();
      }
      // The writer loads retained rows privately once. Only subsequent event
      // changes cross its isolate boundary during normal collection.
      _archiveWriter?.initializeRetainedEvents(_eventsById.keys);
      _ready = true;
      if (enabled) {
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
      await _persist(force: true);
    } catch (_) {
      _storageHealthy = false;
      _lastError = 'sink_unavailable';
      _enabled.value = false;
      _clearMemory();
      if (!_ready) {
        _archiveWriter?.initializeRetainedEvents(const <String>[]);
        _ready = true;
      }
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
    CallDiagnosticPersist? persist,
    Bridge? bridge,
    Future<bool> Function()? networkAllowed,
    Future<dynamic> Function(String method, Map<String, Object?> data)? native,
  }) async {
    await _instance.dispose();
    final value = CallDiagnostics._();
    _instance = value;
    if (now != null) value._now = now;
    value._testUpload = upload;
    value._testPersist = persist;
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
    await _persist(force: true);
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
    await _persist(force: true);
    await _syncNativeConsent();
    await _syncConsent();
  }

  Future<Map<String, Object?>> status() async => {
    'enabled': enabled,
    'retainedEvents': _events.length,
    'queuedEvents': _eventsById.length - _uploaded.length,
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
    'traceCodes': _groups.keys.toList(),
  };

  Future<String> exportPreview() async {
    await _persist();
    final header = <String, Object?>{
      'schemaVersion': 1,
      'exportedAtMs': _nowMs,
      'retentionDays': 7,
      'droppedEvents': _dropped,
    };
    if (_testPersist == null && _storageHealthy && _directory != null) {
      try {
        // Only a path and a small public header cross the UI isolate boundary.
        return await _readCallDiagnosticPreview(_stateFile.path, header);
      } catch (_) {
        // Retained in-memory evidence remains useful if storage disappears.
      }
    }
    return _encodeCallDiagnosticPreview({
      ...header,
      'events': _eventSnapshot(),
    });
  }

  Future<List<Map<String, Object?>>> eventsForTesting() async {
    await _persist();
    return _events.map((e) => Map<String, Object?>.from(e)).toList();
  }

  Future<void> flush() async {
    if (_flushing) {
      // Joining an earlier upload also persists events admitted since its
      // snapshot. The existing upload future alone cannot provide that barrier.
      await Future.wait<void>([
        if (_flushDone case final done?) done.future,
        _persist(),
      ]);
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
            if (_addUploaded(event['eventId']! as String)) {
              acknowledged++;
              _dropped++;
            }
          }
        }
      }
      if (!enabled || epoch != _consentEpoch) return;
      for (final event in batch) {
        if (accepted.contains(event['eventId'])) {
          if (_addUploaded(event['eventId']! as String)) acknowledged++;
        }
      }
      // Rows can be evicted while their upload is pending. Retain completion
      // accounting without leaving obsolete IDs in the persisted index.
      for (final event in batch) {
        final id = event['eventId']! as String;
        if (!_eventsById.containsKey(id)) _removeUploaded(id);
      }
      if (acknowledged == 0) {
        _uploadFailed('bridge_unavailable');
      } else {
        _lastUploadAtMs = _nowMs;
        _uploadFailures = 0;
        _nextUploadAtMs = 0;
        _lastError = 'none';
      }
      await _persist(force: acknowledged > 0);
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
      unawaited(_persist());
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _timer?.cancel();
    _persistTimer?.cancel();
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    await _flushDone?.future;
    await _persist();
    _disposed = true;
    await _archiveWriter?.dispose();
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
    if (_eventsById.containsKey(event['eventId'])) return;
    if ((event['occurredAtMs'] as int) < _nowMs - _retention.inMilliseconds) {
      return;
    }
    final group = trace is String ? _groups[trace] : null;
    final terminal = event['stage'] == 'terminal';
    if (!terminal &&
        ((group?.events.length ?? 0) >= _maxEvents ||
            (group?.bytes ?? 0) + _eventSize(event) > _maxAttemptBytes)) {
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
      final eventBytes = _eventSize(event);
      while (group != null &&
          (group.events.length >= _maxEvents ||
              group.bytes + eventBytes + 256 > _maxAttemptBytes) &&
          group.events.isNotEmpty) {
        _removeEvent(group.events.values.first);
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
    _indexEvent(event);
    _enforceArchiveQuota();
    _schedulePersist();
  }

  void _indexEvent(Map<String, Object?> event) {
    final id = event['eventId']! as String;
    if (_eventsById.containsKey(id)) return;
    final order = _nextEventOrder++;
    _eventsById[id] = event;
    _eventOrder[id] = order;
    final expiry =
        (event['occurredAtMs']! as int) + _retention.inMilliseconds + 1;
    if (_nextExpiryMs == null || expiry < _nextExpiryMs!) {
      _nextExpiryMs = expiry;
    }
    final bytes = _eventSize(event);
    _retainedBytes += bytes;
    if (event['traceId'] case final String trace) {
      final group = _groups.putIfAbsent(trace, _CallDiagnosticGroup.new);
      group.events[order] = event;
      group.bytes += bytes;
    }
    if (_ready) _archiveWriter?.stageEvent(event);
  }

  void _removeEvent(Map<String, Object?> event) {
    final id = event['eventId']! as String;
    if (_eventsById.remove(id) == null) return;
    final bytes = _eventSizes.remove(id) ?? 0;
    final order = _eventOrder.remove(id);
    _retainedBytes -= bytes;
    _removeUploaded(id);
    if (_ready) _archiveWriter?.removeEvent(id);
    if (event['traceId'] case final String trace) {
      final group = _groups[trace]!;
      group.events.remove(order);
      group.bytes -= bytes;
      if (group.events.isEmpty) {
        _groups.remove(trace);
        _cleanupTraceMetadata(trace);
      }
    }
    _dirty = true;
  }

  void _enforceArchiveQuota() {
    while (_groups.length > _maxAttempts) {
      // At most 101 groups are inspected, regardless of retained event count.
      final first = _groups.entries.reduce(
        (a, b) =>
            a.value.events.firstKey()! < b.value.events.firstKey()! ? a : b,
      );
      final trace = first.key;
      _dropped += first.value.events.length;
      for (final event in first.value.events.values.toList()) {
        _removeEvent(event);
      }
      _open.remove(trace);
      _cleanupTraceMetadata(trace);
      _calls.removeWhere((_, id) => id == trace);
      _handles.removeWhere((_, id) => id == trace);
    }
    while (_retainedBytes > _maxBytes - 128 * 1024 && _events.isNotEmpty) {
      _removeEvent(_events.first);
      _dropped++;
    }
  }

  void _rebind(String from, String to) {
    _traceAliases.updateAll((_, id) => id == from ? to : id);
    _traceAliases[from] = to;
    if (_traceAliases.length > 200) {
      _traceAliases.remove(_traceAliases.keys.first);
    }
    final sourceGroup = _groups[from];
    for (final event
        in sourceGroup?.events.values.toList() ??
            const <Map<String, Object?>>[]) {
      if (!_uploaded.contains(event['eventId']) &&
          !_uploading.contains(event['eventId'])) {
        final id = event['eventId']! as String;
        final bytes = _eventSize(event);
        final order = _eventOrder[id]!;
        sourceGroup!.events.remove(order);
        sourceGroup.bytes -= bytes;
        event['traceId'] = to;
        final target = _groups.putIfAbsent(to, _CallDiagnosticGroup.new);
        target.events[order] = event;
        target.bytes += bytes;
        if (_ready) _archiveWriter?.stageEvent(event);
      }
    }
    if (sourceGroup?.events.isEmpty == true) _groups.remove(from);
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

  void _cleanupTraceMetadata(String trace) {
    if (_groups.containsKey(trace) || _open.containsKey(trace)) return;
    _roles.remove(trace);
    _finished.remove(trace);
    _traceDropped.remove(trace);
    _traceAliases.removeWhere((_, id) => id == trace);
  }

  void _prune({bool force = false}) {
    final now = _nowMs;
    if (!force && (_nextExpiryMs == null || now < _nextExpiryMs!)) return;
    final cutoff = now - _retention.inMilliseconds;
    // Periodic writes do not revisit retained history until an actual expiry.
    _nextExpiryMs = null;
    for (final event
        in _events.where((e) => (e['occurredAtMs'] as int) < cutoff).toList()) {
      _removeEvent(event);
    }
    _enforceArchiveQuota();
    for (final trace in _open.keys.toList()) {
      if ((_open[trace]!['startedAtMs'] as int) >= cutoff) continue;
      _open.remove(trace);
      _cleanupTraceMetadata(trace);
      _dirty = true;
    }
    for (final event in _events) {
      final expiry =
          (event['occurredAtMs']! as int) + _retention.inMilliseconds + 1;
      if (_nextExpiryMs == null || expiry < _nextExpiryMs!) {
        _nextExpiryMs = expiry;
      }
    }
    for (final open in _open.values) {
      final expiry =
          (open['startedAtMs']! as int) + _retention.inMilliseconds + 1;
      if (_nextExpiryMs == null || expiry < _nextExpiryMs!) {
        _nextExpiryMs = expiry;
      }
    }
    if (force) {
      // Saved metadata may contain obsolete IDs. Runtime removals already keep
      // these indexes current and do not need a whole-archive reconciliation.
      _uploaded.removeWhere((id) => !_eventsById.containsKey(id));
      final retained = {..._groups.keys, ..._open.keys};
      _roles.removeWhere((id, _) => !retained.contains(id));
      _finished.removeWhere((id) => !retained.contains(id));
      _traceDropped.removeWhere((id, _) => !retained.contains(id));
      _traceAliases.removeWhere((_, id) => !retained.contains(id));
    }
  }

  void _clearMemory() {
    if (_ready) _archiveWriter?.clearEvents();
    _eventsById.clear();
    _groups.clear();
    _eventOrder.clear();
    _retainedBytes = 0;
    _nextExpiryMs = null;
    _uploaded.clear();
    _uploadedAdditions.clear();
    _uploadedRemovals.clear();
    _fullMetadataRequired = true;
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

  bool _addUploaded(String id) {
    if (!_uploaded.add(id)) return false;
    if (!_uploadedRemovals.remove(id)) _uploadedAdditions.add(id);
    _dirty = true;
    return true;
  }

  void _removeUploaded(String id) {
    if (!_uploaded.remove(id)) return;
    if (!_uploadedAdditions.remove(id)) _uploadedRemovals.add(id);
    _dirty = true;
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
    () => _callDiagnosticJsonBytes.count(event),
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
      await _persist(force: true);
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
    await _persist(force: true);
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
    await _persist(force: true);
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
    if (nativeDropped != _nativeDroppedSeen) _dirty = true;
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
    final ack = <String>[];
    for (final raw in (result['events'] as List).take(64)) {
      final event = validateEvent(raw);
      if (event == null ||
          (event['source'] != 'ios' && event['source'] != 'android')) {
        _dropped++;
        _dirty = true;
        if (raw is Map) {
          final id = _validId(raw['eventId']);
          if (id != null) ack.add(id);
        }
        continue;
      }
      final id = event['eventId']! as String;
      if (!_eventsById.containsKey(id)) _append(event);
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
  int get _nowMs => _now().millisecondsSinceEpoch;

  void _schedulePersist() {
    if (_directory == null || _disposed) return;
    _dirty = true;
    // A fixed window bounds both write amplification and crash-loss exposure
    // during sustained samples. Explicit flush/consent/lifecycle bypasses it.
    _persistTimer ??= Timer(const Duration(seconds: 1), () {
      _persistTimer = null;
      unawaited(_persist());
    });
  }

  List<Map<String, Object?>> _eventSnapshot() =>
      _events.map((event) => Map<String, Object?>.from(event)).toList();

  Future<void> _persist({bool force = false}) {
    if (_directory == null || _disposed) return Future<void>.value();
    _persistTimer?.cancel();
    _persistTimer = null;
    if (force) _dirty = true;
    _prune();
    if (_writing case final writing?) {
      if (_dirty) _urgentWriteRequested = true;
      return writing;
    }
    if (!_dirty) return Future<void>.value();
    final completer = Completer<void>();
    _writing = completer.future;
    unawaited(() async {
      try {
        while (_dirty &&
            (_persistTimer == null || _urgentWriteRequested) &&
            !_disposed) {
          _persistTimer?.cancel();
          _persistTimer = null;
          _urgentWriteRequested = false;
          _prune();
          _dirty = false;
          final fullMetadata = _fullMetadataRequired;
          final uploadedAdditions = _uploadedAdditions;
          final uploadedRemovals = _uploadedRemovals;
          _fullMetadataRequired = false;
          _uploadedAdditions = {};
          _uploadedRemovals = {};
          final snapshot = <String, Object?>{
            'schemaVersion': 1,
            'enabled': _enabled.value,
            'consentEpoch': _consentEpoch,
            'consentPending': _consentPending,
            'clearPending': _clearPending,
            'nativeClearPending': _nativeClearPending,
            'lastUploadAtMs': _lastUploadAtMs,
            'dropped': _dropped,
            'nativeDroppedSeen': _nativeDroppedSeen,
            'traceDropped': Map<String, int>.of(_traceDropped),
            'traceAliases': Map<String, String>.of(_traceAliases),
            if (fullMetadata || _testPersist != null)
              'uploaded': _uploaded.toList(),
            'open': {
              for (final entry in _open.entries)
                entry.key: Map<String, Object?>.of(entry.value),
            },
          };
          if (_testPersist case final persist?) {
            await persist(_stateFile.path, {
              ...snapshot,
              'events': _eventSnapshot(),
            });
          } else {
            // Ordinary writes transfer only changed ACK IDs. The worker keeps
            // applied deltas through recoverable sink failures, just like rows.
            await _archiveWriter!.persist(
              snapshot,
              metadataDelta: fullMetadata
                  ? null
                  : DiagnosticArchiveMetadataDelta(
                      setAdditions: {
                        if (uploadedAdditions.isNotEmpty)
                          'uploaded': uploadedAdditions.toList(growable: false),
                      },
                      setRemovals: {
                        if (uploadedRemovals.isNotEmpty)
                          'uploaded': uploadedRemovals.toList(growable: false),
                      },
                    ),
            );
          }
          _storageHealthy = true;
        }
      } catch (_) {
        _dirty = true;
        _fullMetadataRequired = true;
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
    const hex = '0123456789abcdef';
    final codeUnits = Uint8List(36);
    var output = 0;
    var randomWord = 0;
    for (var index = 0; index < 16; index++) {
      // Four secure 32-bit draws provide the same 128 random bits with fewer
      // native entropy calls. UUID version/variant still reserve only six bits.
      if ((index & 3) == 0) randomWord = _random.nextInt(0x100000000);
      var byte = randomWord & 255;
      randomWord >>= 8;
      if (index == 6) byte = (byte & 15) | 64;
      if (index == 8) byte = (byte & 63) | 128;
      if (index == 4 || index == 6 || index == 8 || index == 10) {
        codeUnits[output++] = 45;
      }
      codeUnits[output++] = hex.codeUnitAt(byte >> 4);
      codeUnits[output++] = hex.codeUnitAt(byte & 15);
    }
    return String.fromCharCodes(codeUnits);
  }

  static String? _validId(Object? value) =>
      value is String && _uuid.hasMatch(value) ? value.toLowerCase() : null;
  static int _boundedInt(Object? value) =>
      value is int && value >= 0 && value <= 9007199254740991 ? value : 0;
  static String _snake(String value) =>
      value.replaceAllMapped(_uppercase, (m) => '_${m[0]!.toLowerCase()}');
  static String _closed(String field, Object? value, String fallback) {
    if (value is! String) return fallback;
    final options = _schemaSets[field]!;
    if (options.contains(value)) return value;
    final normalized = _snake(value);
    return options.contains(normalized) ? normalized : fallback;
  }

  static Map<String, Object?> _safeValues(Map values) {
    final result = <String, Object?>{};
    final booleans = _schemaSets['booleanValues']!;
    final integers = _schemaSets['integerValues']!;
    for (final entry in values.entries) {
      final key = entry.key, value = entry.value;
      if (booleans.contains(key) && value is bool) {
        result[key as String] = value;
      }
      if (integers.contains(key) &&
          value is int &&
          value >= 0 &&
          value <= 9007199254740991) {
        result[key as String] = value;
      }
      final options = _enumValues[key];
      if (options != null && value is String) {
        if (options.contains(value)) {
          result[key as String] = value;
        } else {
          final normalized = _snake(value);
          if (options.contains(normalized)) result[key as String] = normalized;
        }
      }
    }
    return result;
  }

  /// Rejects whole foreign records rather than laundering arbitrary strings.
  static Map<String, Object?>? validateEvent(Object? raw) {
    if (raw is! Map || raw['schemaVersion'] != 1) return null;
    try {
      if (raw.keys.any((k) => k is! String || !_eventKeys.contains(k))) {
        return null;
      }
      for (final key in _schemaSets['required']!) {
        if (!raw.containsKey(key)) return null;
      }
      for (final key in _schemaSets['uuidFields']!) {
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
        if (!_schemaSets[key]!.contains(raw[key])) {
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
              !_buildPattern.hasMatch(raw['build'] as String))) {
        return null;
      }
      if (_callDiagnosticJsonBytes.count(raw) > 4096) return null;
      return Map<String, Object?>.from(raw);
    } catch (_) {
      return null;
    }
  }
}
