import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../bridge/bridge.dart';
import 'app_diagnostic_schema.dart';
import 'app_diagnostic_events.dart';

typedef AppDiagnosticUpload =
    Future<Set<String>> Function(List<Map<String, Object?>> events);

/// Observation only: bounded, consent-controlled reports never own an operation.
/// Private operation keys exist only in memory; the archive accepts a closed
/// schema and independently generated diagnostic UUIDs.
final class AppDiagnostics with WidgetsBindingObserver {
  AppDiagnostics._();

  static AppDiagnostics _instance = AppDiagnostics._();
  static AppDiagnostics get instance => _instance;
  static const _channel = MethodChannel('mknoon/app_diagnostics');
  static final Object _attemptContext = Object();
  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );
  static final _buildPattern = RegExp(r'^[0-9A-Za-z][0-9A-Za-z.+_-]{0,79}$');
  static final _hashPattern = RegExp(r'^[0-9a-f]{64}$');
  static const _maxBytes = 4 * 1024 * 1024;
  static const _retentionMs = 7 * 24 * 60 * 60 * 1000;
  final _random = Random.secure();
  final _enabled = ValueNotifier(false);
  final _events = <Map<String, Object?>>[];
  final _eventSizes = <String, int>{};
  final _uploaded = <String>{};
  final _bindings = <String, String>{};
  final _bindingTimes = <String, int>{};
  String _bindingSalt = '';
  final _attempts = <String, String>{};
  final _open = <String, Map<String, Object?>>{};
  final _finished = <String>{};
  final _elapsed = Stopwatch();
  DateTime Function() _now = DateTime.now;
  Directory? _directory;
  Bridge? _bridge;
  Future<bool> Function()? _networkAllowed;
  AppDiagnosticUpload? _testUpload;
  Future<dynamic> Function(String, Map<String, Object?>)? _testNative;
  Future<void>? _writing;
  bool _writeRequested = false;
  Future<void>? _flushFuture;
  Timer? _timer;
  bool _native = false;
  bool _observing = false;
  bool _ready = false;
  bool _disposed = false;
  bool _storageHealthy = true;
  bool _nativeHealthy = true;
  bool _consentPending = true;
  bool _nativeConsentPending = true;
  bool _clearPending = false;
  bool _nativeClearPending = false;
  String _runId = '';
  String _build = 'unknown';
  String _lastError = 'none';
  int _sequence = 0;
  int _epoch = 0;
  int _dropped = 0;
  int _nativeDroppedSeen = 0;
  int _lastUpload = 0;
  int _retryAt = 0;
  int _failures = 0;
  int _lastConfigure = 0;
  int _lastHealth = 0;
  int _storageSuccesses = 0;
  int _storageMaxDuration = 0;
  void Function(bool, int)? _storageObserver;

  bool get enabled => _enabled.value && !_disposed;
  ValueListenable<bool> get enabledListenable => _enabled;
  String? get supportCode => enabled && _ready ? _runId : null;
  int get _nowMs => _now().millisecondsSinceEpoch;
  File get _file => File('${_directory!.path}/state.json');
  static bool isValidTraceId(Object? value) =>
      value is String && _uuid.hasMatch(value);

  String _newId() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  Future<void> initialize({
    required Directory directory,
    Bridge? bridge,
    Future<bool> Function()? networkAllowed,
    String build = 'unknown',
    bool useNative = true,
    bool? enabledOverride,
  }) async {
    if (_disposed) return;
    if (_ready || _directory != null) {
      attachTransport(bridge: bridge, networkAllowed: networkAllowed);
      return;
    }
    _directory = directory;
    // Application bootstrap may attach the transport while optional storage
    // initialization is still pending. Preserve that transport and its privacy
    // gate when initialization has no newer configuration to supply.
    _bridge = bridge ?? _bridge;
    _networkAllowed = networkAllowed ?? _networkAllowed;
    _build = _buildPattern.hasMatch(build) ? build : 'unknown';
    _native = useNative && !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    _runId = _newId();
    _bindingSalt = List.generate(
      32,
      (_) => _random.nextInt(256),
    ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    _elapsed.start();
    try {
      await directory.create(recursive: true);
      if (await _file.exists()) {
        if (await _file.length() > _maxBytes + 1024 * 1024) {
          throw const FormatException('quota');
        }
        final raw = jsonDecode(await _file.readAsString());
        if (raw is! Map ||
            raw['schemaVersion'] != 1 ||
            raw['enabled'] is! bool) {
          throw const FormatException('state');
        }
        _enabled.value = raw['enabled'] == true;
        _epoch = _integer(raw['consentEpoch']);
        _clearPending = raw['clearPending'] == true;
        _nativeClearPending = raw['nativeClearPending'] == true;
        _dropped = _integer(raw['dropped']);
        _nativeDroppedSeen = _integer(raw['nativeDroppedSeen']);
        _lastUpload = _integer(raw['lastUploadAtMs']);
        if (raw['bindingSalt'] is String &&
            _hashPattern.hasMatch(raw['bindingSalt'] as String)) {
          _bindingSalt = raw['bindingSalt'] as String;
          if (raw['bindings'] case final Map bindings) {
            for (final entry in bindings.entries.take(1000)) {
              final value = entry.value;
              if (entry.key is String &&
                  _hashPattern.hasMatch(entry.key as String) &&
                  value is Map &&
                  isValidTraceId(value['traceId'])) {
                final at = _integer(value['updatedAtMs']);
                if (at >= _nowMs - _retentionMs && at <= _nowMs) {
                  _bindings[entry.key as String] = value['traceId'] as String;
                  _bindingTimes[entry.key as String] = at;
                }
              }
            }
          }
        }
        if (raw['events'] case final List records) {
          for (final item in records) {
            final event = validateEvent(item);
            if (event != null) _events.add(event);
          }
        }
        if (raw['uploaded'] case final List ids) {
          _uploaded.addAll(ids.whereType<String>().where(isValidTraceId));
        }
        if (raw['open'] case final List pending) {
          for (final item in pending.take(100)) {
            if (item is Map &&
                _closed('feature', item['feature']) &&
                isValidTraceId(item['traceId']) &&
                isValidTraceId(item['attemptId'])) {
              final value = Map<String, Object?>.from(item);
              _open[item['attemptId'] as String] = {
                'feature': value['feature'],
                'traceId': value['traceId'],
                'attemptId': value['attemptId'],
              };
            }
          }
        }
      } else {
        _enabled.value = true;
      }
      if (enabledOverride != null) _enabled.value = enabledOverride;
      if (_epoch == 0) _epoch = max(1, _nowMs);
      _ready = true;
      _finished.addAll(
        _events
            .where((event) => event['stage'] == 'finish')
            .map((event) => event['attemptId'])
            .whereType<String>(),
      );
      _open.removeWhere((id, _) => _finished.contains(id));
      _storageObserver = (successful, duration) {
        if (!enabled) return;
        if (successful) {
          _storageSuccesses = min(_storageSuccesses + 1, 1000000000);
          _storageMaxDuration = max(_storageMaxDuration, duration);
        } else {
          record(
            feature: 'storage',
            stage: 'commit',
            outcome: 'failed',
            reason: 'storage_failed',
            values: {'durationMs': duration, 'count': 1},
          );
        }
      };
      AppDiagnosticEvents.onStorageTransaction = _storageObserver;
      if (!enabled) {
        _clearMemory();
      } else {
        _prune();
        for (final pending in List<Map<String, Object?>>.of(_open.values)) {
          final feature = pending['feature'] as String;
          final trace = pending['traceId'] as String;
          _attempts['$feature:$trace'] = pending['attemptId'] as String;
          finishAttempt(
            feature: feature,
            traceId: trace,
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
    await _syncNative();
    if (useNative) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
      _timer = Timer.periodic(const Duration(seconds: 10), (_) {
        unawaited(flush());
      });
    }
    unawaited(flush());
  }

  void attachTransport({
    Bridge? bridge,
    Future<bool> Function()? networkAllowed,
  }) {
    if (bridge != null) _bridge = bridge;
    if (networkAllowed != null) _networkAllowed = networkAllowed;
    _lastConfigure = 0;
    _retryAt = 0;
    unawaited(flush());
  }

  static Future<AppDiagnostics> installForTesting({
    Directory? directory,
    bool? enabled = true,
    DateTime Function()? now,
    AppDiagnosticUpload? upload,
    Bridge? bridge,
    Future<bool> Function()? networkAllowed,
    Future<dynamic> Function(String, Map<String, Object?>)? native,
  }) async {
    await _instance.dispose();
    final instance = AppDiagnostics._();
    _instance = instance;
    if (now != null) instance._now = now;
    instance._testUpload = upload;
    instance._testNative = native;
    await instance.initialize(
      directory:
          directory ??
          await Directory.systemTemp.createTemp('app-diagnostics-'),
      enabledOverride: enabled,
      useNative: false,
      bridge: bridge,
      networkAllowed: networkAllowed,
    );
    await instance.flush();
    return instance;
  }

  String? traceForOperation(String privateKey, {String? propagatedTraceId}) {
    if (!enabled || !_ready || privateKey.isEmpty) return null;
    // This keyed local lookup is never included in exports or relay payloads.
    // A fresh random salt prevents guessing/cross-install matching of private
    // operation IDs; clearing or opting out rotates it and drops the index.
    final key = Hmac(
      sha256,
      utf8.encode(_bindingSalt),
    ).convert(utf8.encode(privateKey)).toString();
    if ((_bindingTimes[key] ?? _nowMs) < _nowMs - _retentionMs) {
      _bindings.remove(key);
      _bindingTimes.remove(key);
    }
    if (isValidTraceId(propagatedTraceId)) {
      _bindings[key] = propagatedTraceId!;
    }
    final result = _bindings.putIfAbsent(key, _newId);
    _bindingTimes[key] = _nowMs;
    while (_bindings.length > 1000) {
      final oldest = _bindings.keys.first;
      _bindings.remove(oldest);
      _bindingTimes.remove(oldest);
    }
    unawaited(_persist());
    return result;
  }

  String? _attemptFor(String feature, String? traceId) {
    final key = '$feature:${traceId ?? ''}';
    final scoped = Zone.current[_attemptContext];
    if (scoped is Map<String, String> && scoped.containsKey(key)) {
      return scoped[key];
    }
    return _attempts[key];
  }

  /// Each invocation gets its own attempt while preserving a cross-peer trace.
  /// Async continuations retain this scope, so a concurrent rejected request
  /// cannot finish another invocation's valid transfer.
  T runWithAttempt<T>({
    required String feature,
    String? traceId,
    required T Function(String? traceId) body,
  }) {
    final trace = startAttempt(
      feature: feature,
      traceId: traceId,
      newAttempt: true,
    );
    final key = '$feature:${trace ?? ''}';
    final attempt = _attempts[key];
    final parent = Zone.current[_attemptContext];
    return runZoned(
      () => body(trace),
      zoneValues: {
        _attemptContext: <String, String>{
          if (parent is Map<String, String>) ...parent,
          key: ?attempt,
        },
      },
    );
  }

  String? startAttempt({
    required String feature,
    String? traceId,
    bool newAttempt = false,
  }) {
    if (!enabled || !_ready || !_closed('feature', feature)) return null;
    final trace = isValidTraceId(traceId) ? traceId! : _newId();
    final key = '$feature:$trace';
    final previous = _attemptFor(feature, trace);
    if (!newAttempt && previous != null && _open.containsKey(previous)) {
      return trace;
    }
    final attempt = _newId();
    _attempts[key] = attempt;
    _open[attempt] = {
      'feature': feature,
      'traceId': trace,
      'attemptId': attempt,
    };
    runZoned(
      () => record(
        feature: feature,
        stage: 'start',
        outcome: 'started',
        traceId: trace,
      ),
      zoneValues: {
        _attemptContext: <String, String>{key: attempt},
      },
    );
    return trace;
  }

  bool record({
    required String feature,
    required String stage,
    required String outcome,
    String reason = 'none',
    String? traceId,
    Map<String, Object?> values = const {},
  }) {
    if (!enabled || !_ready || !_storageHealthy) return false;
    try {
      final attempt = _attemptFor(feature, traceId);
      final event = validateEvent({
        'schemaVersion': 1,
        'eventId': _newId(),
        'source': 'flutter',
        'runId': _runId,
        'sequence': ++_sequence,
        'occurredAtMs': _nowMs,
        'elapsedMs': _elapsed.elapsedMilliseconds,
        'feature': feature,
        'stage': stage,
        'outcome': outcome,
        'reason': reason,
        'build': _build,
        'platform': kIsWeb ? 'web' : Platform.operatingSystem,
        if (isValidTraceId(traceId)) 'traceId': traceId,
        'attemptId': ?attempt,
        'values': values,
      });
      if (event == null) {
        _dropped++;
        return false;
      }
      final retained = _append(event);
      unawaited(_persist());
      return retained;
    } catch (_) {
      _dropped++;
      return false;
    }
  }

  void finishAttempt({
    required String feature,
    required String? traceId,
    required String outcome,
    String reason = 'none',
    Map<String, Object?> values = const {},
  }) {
    if (!enabled || !isValidTraceId(traceId)) return;
    final attempt = _attemptFor(feature, traceId);
    if (attempt == null || _finished.contains(attempt)) return;
    if (!_closed('outcome', outcome) || !_closed('reason', reason)) return;
    final retained = record(
      feature: feature,
      stage: 'finish',
      outcome: outcome,
      reason: reason,
      traceId: traceId,
      values: values,
    );
    if (retained) {
      _finished.add(attempt);
      _open.remove(attempt);
      unawaited(_persist());
    }
  }

  void captureError(
    Object error,
    StackTrace? stack, {
    String reason = 'unhandled_error',
  }) {
    // Only static app source locations enter the fingerprint input. Never
    // stringify the exception: messages commonly contain file paths or content.
    final kind = switch (error) {
      TimeoutException() => 'timeout',
      FileSystemException() => 'file_system',
      PlatformException() || MissingPluginException() => 'platform',
      FormatException() => 'format',
      ArgumentError() => 'argument',
      StateError() => 'state',
      _ => 'other',
    };
    final frames =
        RegExp(r'package:flutter_app/[A-Za-z0-9_./]+\.dart:\d+(?::\d+)?')
            .allMatches(stack?.toString() ?? '')
            .take(12)
            .map((m) => m.group(0))
            .join('|');
    record(
      feature: 'runtime',
      stage: 'process',
      outcome: 'failed',
      reason: reason,
      values: {
        'errorClass': kind,
        'fingerprint': sha256.convert(utf8.encode('$kind|$frames')).toString(),
      },
    );
  }

  Future<void> setEnabled(bool value) async {
    if (!_ready || _disposed || value == enabled) return;
    _epoch = max(_epoch + 1, _nowMs);
    _enabled.value = value;
    _consentPending = true;
    _nativeConsentPending = true;
    if (!value) {
      _nativeClearPending = true;
      _clearMemory();
    }
    _retryAt = 0;
    await _persist();
    await _syncNative();
    await _syncConsent(_epoch);
    if (enabled) unawaited(flush());
  }

  Future<void> clear() async {
    if (!_ready || _disposed) return;
    _epoch = max(_epoch + 1, _nowMs);
    _clearPending = true;
    _nativeClearPending = true;
    _consentPending = true;
    _nativeConsentPending = true;
    _clearMemory();
    _retryAt = 0;
    await _persist();
    await _syncNative();
    await _syncConsent(_epoch);
    if (enabled) unawaited(flush());
  }

  void _clearMemory() {
    _events.clear();
    _eventSizes.clear();
    _uploaded.clear();
    _open.clear();
    _attempts.clear();
    _finished.clear();
    _bindings.clear();
    _bindingTimes.clear();
    _bindingSalt = List.generate(
      32,
      (_) => _random.nextInt(256),
    ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    _lastUpload = 0;
    _dropped = 0;
    _nativeDroppedSeen = 0;
    _storageSuccesses = 0;
    _storageMaxDuration = 0;
  }

  Future<Map<String, Object?>> status() async => {
    'enabled': enabled,
    'retainedEvents': _events.length,
    'queuedEvents': _events
        .where((e) => !_uploaded.contains(e['eventId']))
        .length,
    'droppedEvents': _dropped,
    'lastUploadAtMs': _lastUpload,
    'storageHealthy': _storageHealthy && _ready,
    'nativeStorageHealthy': _nativeHealthy,
    'consentPending':
        _consentPending || _nativeConsentPending || _nativeClearPending,
    'lastError': _lastError,
    if (supportCode != null) 'supportCode': supportCode,
  };

  Future<String> exportPreview() async {
    await _persist();
    return const JsonEncoder.withIndent('  ').convert({
      'schemaVersion': 1,
      'runId': _runId,
      'status': await status(),
      'events': _events,
    });
  }

  Future<List<Map<String, Object?>>> eventsForTesting() async {
    await _persist();
    return _events.map((e) => Map<String, Object?>.from(e)).toList();
  }

  Future<void> flush() {
    if (_disposed || !_ready) return Future.value();
    final existing = _flushFuture;
    if (existing != null) return existing;
    final future = _flush();
    _flushFuture = future;
    return future.whenComplete(() {
      if (identical(_flushFuture, future)) _flushFuture = null;
    });
  }

  Future<void> _flush() async {
    try {
      await _syncNative();
      final epoch = _epoch;
      if (enabled) await _drainNative(epoch);
      await _persist();
      if (epoch != _epoch || !_storageHealthy || _nowMs < _retryAt) return;
      if (_testUpload == null) {
        if (_bridge?.isInitialized != true) return;
        if (_consentPending ||
            _clearPending ||
            _lastConfigure == 0 ||
            _nowMs - _lastConfigure >= 300000) {
          if (!await _syncConsent(epoch)) {
            _backoff('bridge_unavailable');
            return;
          }
        }
      }
      if (!enabled || epoch != _epoch) return;
      if (_nowMs - _lastHealth >= 300000) {
        _lastHealth = _nowMs;
        if (_storageSuccesses > 0) {
          record(
            feature: 'storage',
            stage: 'snapshot',
            outcome: 'ok',
            values: {
              'count': _storageSuccesses,
              'durationMs': _storageMaxDuration,
            },
          );
          _storageSuccesses = 0;
          _storageMaxDuration = 0;
        }
        record(
          feature: 'runtime',
          stage: 'snapshot',
          outcome: 'ok',
          values: {
            'queuedEvents': _events
                .where((e) => !_uploaded.contains(e['eventId']))
                .length,
            'droppedEvents': _dropped,
            'storageHealthy': _storageHealthy,
            'nativeHealthy': _nativeHealthy,
            'consentPending': _consentPending,
          },
        );
      }
      final pending =
          _events.where((e) => !_uploaded.contains(e['eventId'])).toList()
            ..sort(
              (a, b) => (a['stage'] == 'finish' ? 0 : 1).compareTo(
                b['stage'] == 'finish' ? 0 : 1,
              ),
            );
      final batch = pending
          .take(64)
          .map((e) => Map<String, Object?>.from(e))
          .toList();
      if (batch.isEmpty) return;
      final Set<String> accepted;
      final rejected = <String>{};
      if (_testUpload != null) {
        accepted = await _testUpload!(batch);
      } else {
        final result = await _request('upload', {'events': batch}, epoch);
        // A bounded server may acknowledge part of a batch while reporting
        // quota/backpressure for the remainder. Those explicit ACKs still
        // apply; only unacknowledged events should retry.
        if (result?['supported'] != true) {
          _backoff('bridge_unavailable');
          return;
        }
        accepted = (result?['acceptedEventIds'] as List? ?? [])
            .whereType<String>()
            .toSet();
        rejected.addAll(
          (result?['rejectedEventIds'] as List? ?? []).whereType<String>(),
        );
      }
      if (!enabled || epoch != _epoch) return;
      var acknowledged = 0;
      for (final event in batch) {
        final id = event['eventId'] as String;
        if (accepted.contains(id) || rejected.contains(id)) {
          if (_uploaded.add(id)) {
            acknowledged++;
            if (rejected.contains(id)) _dropped++;
          }
        }
      }
      if (acknowledged == 0) {
        _backoff('bridge_unavailable');
      } else {
        _lastUpload = _nowMs;
        _failures = 0;
        _retryAt = 0;
        _lastError = 'none';
      }
      await _persist();
    } catch (_) {
      _backoff('bridge_unavailable');
    }
  }

  Future<Map<String, dynamic>?> _request(
    String op,
    Map<String, Object?> data,
    int epoch,
  ) async {
    final bridge = _bridge;
    if (bridge?.isInitialized != true) return null;
    if (_networkAllowed != null && !await _networkAllowed!()) return null;
    if (_epoch != epoch || (!enabled && op == 'upload')) return null;
    final response = jsonDecode(
      await bridge!
          .send(
            jsonEncode({
              'cmd': 'app_diagnostics_v1',
              'payload': {'op': op, 'consentEpoch': epoch, ...data},
            }),
          )
          .timeout(const Duration(seconds: 5)),
    );
    if (_epoch != epoch ||
        response is! Map ||
        response['ok'] != true ||
        response['data'] is! Map) {
      return null;
    }
    final responseData = Map<String, dynamic>.from(response['data'] as Map);
    if (responseData['consentEpoch'] != null &&
        responseData['consentEpoch'] != epoch) {
      return null;
    }
    return responseData;
  }

  Future<bool> _syncConsent(int epoch) async {
    if (_testUpload != null) return true;
    try {
      // Establish the desired state before clearing: clear preserves consent,
      // and a conflicting configure at the same epoch must remain rejected.
      final result = await _request('configure', {'enabled': enabled}, epoch);
      if (epoch != _epoch ||
          result?['supported'] != true ||
          result?['enabled'] != enabled ||
          result?['reason'] != null) {
        return false;
      }
      if (_clearPending) {
        final result = await _request('clear', {}, epoch);
        if (epoch != _epoch ||
            result?['supported'] != true ||
            result?['reason'] != null) {
          return false;
        }
        _clearPending = false;
      }
      _consentPending = false;
      _lastConfigure = _nowMs;
      await _persist();
      return true;
    } catch (_) {
      return false;
    }
  }

  void _backoff(String reason) {
    _lastError = reason;
    _failures = min(_failures + 1, 6);
    _retryAt = _nowMs + min(300000, 10000 * (1 << (_failures - 1)));
  }

  Future<dynamic> _nativeInvoke(
    String method,
    Map<String, Object?> values,
  ) async {
    if (!_native && _testNative == null) return true;
    final args = {'version': 1, 'consentEpoch': _epoch, ...values};
    try {
      if (_testNative != null) return await _testNative!(method, args);
      return await _channel
          .invokeMethod<dynamic>(method, args)
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      return null;
    }
  }

  Future<void> _syncNative() async {
    final epoch = _epoch;
    if (_nativeConsentPending) {
      final result = await _nativeInvoke('configure', {'enabled': enabled});
      if (epoch != _epoch) return;
      _nativeConsentPending = result != true;
    }
    if (_nativeClearPending) {
      final result = await _nativeInvoke('clear', {});
      if (epoch != _epoch) return;
      _nativeClearPending = result != true;
    }
    _nativeHealthy = !_nativeConsentPending && !_nativeClearPending;
  }

  Future<void> _drainNative(int epoch) async {
    if (!_native && _testNative == null) return;
    final result = await _nativeInvoke('drain', {'limit': 64});
    if (epoch != _epoch ||
        !enabled ||
        result is! Map ||
        result['version'] != 1 ||
        result['events'] is! List) {
      return;
    }
    final dropped = _integer(result['droppedEvents']);
    _dropped += max(0, dropped - _nativeDroppedSeen);
    _nativeDroppedSeen = dropped;
    final known = _events.map((e) => e['eventId']).toSet();
    final ack = <String>[];
    for (final raw in (result['events'] as List).take(64)) {
      final event = validateEvent(raw);
      if (event != null &&
          (event['source'] == 'android' || event['source'] == 'ios')) {
        event['reportingRunId'] = _runId;
        if (known.add(event['eventId'])) _append(event);
        ack.add(event['eventId'] as String);
      } else {
        _dropped++;
        if (raw is Map && isValidTraceId(raw['eventId'])) {
          ack.add(raw['eventId'] as String);
        }
      }
    }
    await _persist();
    if (!_storageHealthy || !enabled || epoch != _epoch) return;
    if (ack.isNotEmpty) await _nativeInvoke('ack', {'eventIds': ack});
  }

  int _eventSize(Map<String, Object?> event) => _eventSizes.putIfAbsent(
    event['eventId'] as String,
    () => utf8.encode(jsonEncode(event)).length,
  );

  bool _append(Map<String, Object?> event) {
    final attempt = event['attemptId'] ?? event['traceId'] ?? event['runId'];
    final group = _events
        .where((e) => (e['attemptId'] ?? e['traceId'] ?? e['runId']) == attempt)
        .toList();
    var size = group.fold<int>(0, (n, e) => n + _eventSize(e));
    final incomingSize = _eventSize(event);
    while (group.length >= 255 || size + incomingSize > 64000) {
      if (event['stage'] != 'finish' || group.isEmpty) {
        _dropped++;
        _eventSizes.remove(event['eventId']);
        return false;
      }
      final old = group.removeAt(0);
      size -= _eventSize(old);
      _events.remove(old);
      // Acknowledged rows were uploaded or already counted as rejected;
      // evicting their local copy does not lose additional evidence.
      if (!_uploaded.remove(old['eventId'])) _dropped++;
    }
    _events.add(event);
    _prune();
    return _events.contains(event);
  }

  void _prune() {
    final expiredBindings = _bindingTimes.entries
        .where((entry) => entry.value < _nowMs - _retentionMs)
        .map((entry) => entry.key)
        .toList();
    for (final key in expiredBindings) {
      _bindings.remove(key);
      _bindingTimes.remove(key);
    }
    _events.removeWhere(
      (e) => _integer(e['occurredAtMs']) < _nowMs - _retentionMs,
    );
    final groups = <String>{};
    for (final event in _events.reversed) {
      groups.add(
        (event['attemptId'] ?? event['traceId'] ?? event['runId']) as String,
      );
    }
    final keep = groups.take(100).toSet();
    _events.removeWhere((e) {
      final remove = !keep.contains(
        e['attemptId'] ?? e['traceId'] ?? e['runId'],
      );
      if (remove && !_uploaded.contains(e['eventId'])) _dropped++;
      return remove;
    });
    var bytes = _events.fold<int>(0, (n, e) => n + _eventSize(e));
    while (bytes > _maxBytes - 128 * 1024 && _events.isNotEmpty) {
      final old = _events.removeAt(0);
      bytes -= _eventSize(old);
      if (!_uploaded.contains(old['eventId'])) _dropped++;
    }
    final ids = _events.map((e) => e['eventId']).toSet();
    _eventSizes.removeWhere((id, _) => !ids.contains(id));
    _uploaded.removeWhere((id) => !ids.contains(id));
    final attempts = _events
        .map((e) => e['attemptId'])
        .whereType<String>()
        .toSet();
    _finished.removeWhere((id) => !attempts.contains(id));
    _open.removeWhere((id, _) => !attempts.contains(id));
    _attempts.removeWhere((_, id) => !attempts.contains(id));
  }

  Future<void> _persist() {
    if (_directory == null || !_ready || _disposed) return Future.value();
    _writeRequested = true;
    final active = _writing;
    if (active != null) return active;
    final completed = Completer<void>();
    _writing = completed.future;
    unawaited(() async {
      while (_writeRequested && !_disposed) {
        _writeRequested = false;
        try {
          _prune();
          final data = jsonEncode({
            'schemaVersion': 1,
            'enabled': enabled,
            'consentEpoch': _epoch,
            'clearPending': _clearPending,
            'nativeClearPending': _nativeClearPending,
            'dropped': _dropped,
            'nativeDroppedSeen': _nativeDroppedSeen,
            'lastUploadAtMs': _lastUpload,
            'bindingSalt': _bindingSalt,
            'bindings': {
              for (final entry in _bindings.entries)
                entry.key: {
                  'traceId': entry.value,
                  'updatedAtMs': _bindingTimes[entry.key],
                },
            },
            'events': _events,
            'uploaded': _uploaded.toList(),
            'open': _open.values.toList(),
          });
          final temporary = File('${_file.path}.new');
          await temporary.writeAsString(data, flush: true);
          await temporary.rename(_file.path);
        } catch (_) {
          _storageHealthy = false;
          _enabled.value = false;
          _lastError = 'sink_unavailable';
          _nativeConsentPending = true;
        }
      }
      _writing = null;
      completed.complete();
    }());
    return completed.future;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _retryAt = 0;
      unawaited(flush());
    } else {
      unawaited(_persist());
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _timer?.cancel();
    if (identical(AppDiagnosticEvents.onStorageTransaction, _storageObserver)) {
      AppDiagnosticEvents.onStorageTransaction = null;
    }
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    await _flushFuture;
    await _persist();
    _disposed = true;
  }

  static int _integer(Object? value) =>
      value is int && value >= 0 && value <= 9007199254740991 ? value : 0;
  static bool _closed(String field, Object? value) =>
      (appDiagnosticSchemaV1[field] as List).contains(value);

  static Map<String, Object?>? validateEvent(Object? raw) {
    if (raw is! Map || raw['schemaVersion'] != 1) return null;
    try {
      final allowed = {
        ...appDiagnosticSchemaV1['required'] as List,
        ...appDiagnosticSchemaV1['optional'] as List,
      };
      if (raw.keys.any((k) => !allowed.contains(k))) return null;
      if ((appDiagnosticSchemaV1['required'] as List).any(
        (k) => !raw.containsKey(k),
      )) {
        return null;
      }
      for (final key in appDiagnosticSchemaV1['uuidFields'] as List) {
        if (raw.containsKey(key) && !isValidTraceId(raw[key])) return null;
      }
      for (final key in [
        'source',
        'platform',
        'feature',
        'stage',
        'outcome',
        'reason',
      ]) {
        if (!_closed(key, raw[key])) return null;
      }
      for (final key in ['sequence', 'occurredAtMs', 'elapsedMs']) {
        if (raw[key] is! int || _integer(raw[key]) != raw[key]) return null;
      }
      if (raw['build'] is! String ||
          !_buildPattern.hasMatch(raw['build'] as String)) {
        return null;
      }
      final values = raw['values'];
      if (values is! Map || values.length > 16) return null;
      for (final entry in values.entries) {
        if ((appDiagnosticSchemaV1['booleanValues'] as List).contains(
          entry.key,
        )) {
          if (entry.value is! bool) return null;
        } else if ((appDiagnosticSchemaV1['integerValues'] as List).contains(
          entry.key,
        )) {
          if (entry.value is! int || _integer(entry.value) != entry.value) {
            return null;
          }
        } else if ((appDiagnosticSchemaV1['hashValues'] as List).contains(
          entry.key,
        )) {
          if (entry.value is! String ||
              !_hashPattern.hasMatch(entry.value as String)) {
            return null;
          }
        } else {
          final options =
              (appDiagnosticSchemaV1['enumValues'] as Map)[entry.key];
          if (options is! List || !options.contains(entry.value)) return null;
        }
      }
      if (utf8.encode(jsonEncode(raw)).length > 4096) return null;
      return {
        ...Map<String, Object?>.from(raw),
        'values': Map<String, Object?>.from(values),
      };
    } catch (_) {
      return null;
    }
  }
}
