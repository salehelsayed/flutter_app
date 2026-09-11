import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../bridge/bridge.dart';
import 'app_diagnostic_schema.dart';
import 'app_diagnostic_events.dart';
import 'diagnostic_archive_writer.dart';

typedef AppDiagnosticUpload =
    Future<Set<String>> Function(List<Map<String, Object?>> events);

typedef AppDiagnosticPersist =
    Future<void> Function(String path, Map<String, Object?> state);

Future<String> _encodeDiagnosticPreview(Map<String, Object?> state) =>
    Isolate.run(() => const JsonEncoder.withIndent('  ').convert(state));

Future<String> _diagnosticPreviewFromFile(
  String path,
  Map<String, Object?> header,
) => Isolate.run(() async {
  final saved = jsonDecode(await File(path).readAsString()) as Map;
  final events = (saved['events'] as List)
      .map(AppDiagnostics.validateEvent)
      .whereType<Map<String, Object?>>()
      .toList();
  // Local binding salts/indexes are deliberately excluded from the export.
  return const JsonEncoder.withIndent(
    '  ',
  ).convert({...header, 'events': events});
});

Future<dynamic> _readDiagnosticState(String path) => Isolate.run(() async {
  final raw = jsonDecode(await File(path).readAsString());
  if (raw is Map && raw['events'] is List) {
    raw['events'] = (raw['events'] as List)
        .map(AppDiagnostics.validateEvent)
        .whereType<Map<String, Object?>>()
        .toList();
  }
  return raw;
});

final class _DiagnosticGroup {
  final events = <String, Map<String, Object?>>{};
  int bytes = 0;
}

final class _NotificationFileLockObservation {
  _NotificationFileLockObservation(this.phase, this.startedMs);

  NotificationFileLockPhase phase;
  int startedMs;
}

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
  static final _allowedFields = <Object?>{
    ...appDiagnosticSchemaV1['required'] as List,
    ...appDiagnosticSchemaV1['optional'] as List,
  };
  static final _closedFields = <String, Set<Object?>>{
    for (final entry in appDiagnosticSchemaV1.entries)
      if (entry.value is List)
        entry.key: Set<Object?>.from(entry.value as List),
  };
  static final _valueEnums = <Object?, Set<Object?>>{
    for (final entry in (appDiagnosticSchemaV1['enumValues'] as Map).entries)
      entry.key: Set<Object?>.from(entry.value as List),
  };
  static final _byteCounter = DiagnosticJsonByteCounter(
    cachedStrings: <String>{
      ..._allowedFields.cast<String>(),
      for (final values in _closedFields.values) ...values.whereType<String>(),
      for (final entry in _valueEnums.entries) entry.key as String,
      for (final values in _valueEnums.values) ...values.whereType<String>(),
    },
  );
  static const _maxBytes = 4 * 1024 * 1024;
  static const _retentionMs = 7 * 24 * 60 * 60 * 1000;
  final _random = Random.secure();
  final _enabled = ValueNotifier(false);
  final _eventsById = <String, Map<String, Object?>>{};
  Iterable<Map<String, Object?>> get _events => _eventsById.values;
  final _groups = <String, _DiagnosticGroup>{};
  int _retainedBytes = 0;
  int? _nextEventExpiryMs;
  final _eventSizes = <String, int>{};
  final _uploaded = <String>{};
  final _bindings = <String, String>{};
  final _bindingTimes = <String, int>{};
  int? _nextBindingExpiryMs;
  bool _fullMetadataRequired = true;
  final _bindingUpserts = <String, Object?>{};
  final _bindingRemovals = <String>{};
  final _uploadedAdditions = <String>{};
  final _uploadedRemovals = <String>{};
  String _bindingSalt = '';
  final _attempts = <String, String>{};
  final _open = <String, Map<String, Object?>>{};
  final _finished = <String>{};
  final _elapsed = Stopwatch();
  DateTime Function() _now = DateTime.now;
  Directory? _directory;
  DiagnosticArchiveWriter? _archiveWriter;
  Bridge? _bridge;
  Future<bool> Function()? _networkAllowed;
  AppDiagnosticUpload? _testUpload;
  AppDiagnosticPersist? _testPersist;
  Future<dynamic> Function(String, Map<String, Object?>)? _testNative;
  Future<void>? _writing;
  bool _writeRequested = false;
  bool _urgentWriteRequested = false;
  Timer? _persistTimer;
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
  void Function(Object, NotificationFileLockPhase)? _notificationLockObserver;
  final _notificationLocks = <Object, _NotificationFileLockObservation>{};
  static const _maxObservedNotificationLocks = 128;
  int _notificationLockDropped = 0;
  bool _notificationLockDirty = false;
  bool _notificationLockInactive = false;
  AppLifecycleState? _notificationLockLifecycle;
  Timer? _notificationLockSnapshotTimer;

  bool get enabled => _enabled.value && !_disposed;
  ValueListenable<bool> get enabledListenable => _enabled;
  String? get supportCode => enabled && _ready ? _runId : null;
  int get _nowMs => _now().millisecondsSinceEpoch;
  File get _file => File('${_directory!.path}/state.json');
  static bool isValidTraceId(Object? value) =>
      value is String && _uuid.hasMatch(value);

  String _newId() {
    // Keep all 122 UUIDv4 random bits, requesting the same 16 secure bytes in
    // four native entropy calls instead of one call per byte.
    final chars = Uint8List(36);
    var offset = 0;
    for (var word = 0; word < 4; word++) {
      var bits = _random.nextInt(0x100000000);
      if (word == 1) bits = (bits & 0xffff0fff) | 0x00004000;
      if (word == 2) bits = (bits & 0x3fffffff) | 0x80000000;
      for (var shift = 28; shift >= 0; shift -= 4) {
        if (offset == 8 || offset == 13 || offset == 18 || offset == 23) {
          chars[offset++] = 45;
        }
        final digit = (bits >>> shift) & 15;
        chars[offset++] = digit < 10 ? 48 + digit : 87 + digit;
      }
    }
    return String.fromCharCodes(chars);
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
    _archiveWriter = DiagnosticArchiveWriter(
      _file.path,
      validateEvent: AppDiagnostics.validateEvent,
    );
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
        final raw = await _readDiagnosticState(_file.path);
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
                  final expiry = at + _retentionMs + 1;
                  _nextBindingExpiryMs = min(
                    _nextBindingExpiryMs ?? expiry,
                    expiry,
                  );
                }
              }
            }
          }
        }
        if (raw['events'] case final List records) {
          for (var index = 0; index < records.length; index++) {
            _append(records[index] as Map<String, Object?>);
            // Rebuilding bounded indexes must also leave room for startup
            // frames when recovering a full archive.
            if (index % 64 == 63) await Future<void>.delayed(Duration.zero);
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
      _archiveWriter!.initializeRetainedEvents(_eventsById.keys);
      _uploaded.removeWhere((id) => !_eventsById.containsKey(id));
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
      _notificationLockObserver = _observeNotificationFileLock;
      AppDiagnosticEvents.onNotificationFileLock = _notificationLockObserver;
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
      await _persist(force: true);
    } catch (_) {
      _storageHealthy = false;
      _lastError = 'sink_unavailable';
      _enabled.value = false;
      _clearMemory();
    }
    await _syncNative();
    if (useNative) {
      _notificationLockLifecycle = WidgetsBinding.instance.lifecycleState;
      _notificationLockInactive =
          _notificationLockLifecycle != null &&
          _notificationLockLifecycle != AppLifecycleState.resumed;
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
    AppDiagnosticPersist? persist,
    Bridge? bridge,
    Future<bool> Function()? networkAllowed,
    Future<dynamic> Function(String, Map<String, Object?>)? native,
  }) async {
    await _instance.dispose();
    final instance = AppDiagnostics._();
    _instance = instance;
    if (now != null) instance._now = now;
    instance._testUpload = upload;
    instance._testPersist = persist;
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
      _removeBinding(key);
    }
    if (isValidTraceId(propagatedTraceId)) {
      _bindings[key] = propagatedTraceId!;
    }
    final result = _bindings.putIfAbsent(key, _newId);
    _bindingTimes[key] = _nowMs;
    _bindingUpserts[key] = {
      'traceId': result,
      'updatedAtMs': _bindingTimes[key],
    };
    // Keep a prior removal in this batch: removing then re-adding an expired
    // binding must also move it to the end of the durable eviction order.
    final expiry = _nowMs + _retentionMs + 1;
    _nextBindingExpiryMs = min(_nextBindingExpiryMs ?? expiry, expiry);
    while (_bindings.length > 1000) {
      final oldest = _bindings.keys.first;
      _removeBinding(oldest);
    }
    _schedulePersist();
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
      final event = _validateEventAndSize({
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
        _schedulePersist();
        return false;
      }
      final retained = _append(event.event, encodedSize: event.bytes);
      _schedulePersist();
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
      _schedulePersist();
    }
  }

  void captureError(
    Object error,
    StackTrace? stack, {
    String reason = 'unhandled_error',
  }) {
    if (!enabled || !_ready || !_storageHealthy) return;
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
        // A class-only hash cannot identify a source boundary. Keep the class
        // observation, but leave the optional fingerprint absent in that case.
        if (frames.isNotEmpty)
          'fingerprint': sha256
              .convert(utf8.encode('$kind|$frames'))
              .toString(),
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
    await _persist(force: true);
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
    await _persist(force: true);
    await _syncNative();
    await _syncConsent(_epoch);
    if (enabled) unawaited(flush());
  }

  void _clearMemory() {
    _archiveWriter?.clearEvents();
    _eventsById.clear();
    _groups.clear();
    _retainedBytes = 0;
    _nextEventExpiryMs = null;
    _eventSizes.clear();
    _uploaded.clear();
    _open.clear();
    _attempts.clear();
    _finished.clear();
    _bindings.clear();
    _bindingTimes.clear();
    _nextBindingExpiryMs = null;
    _fullMetadataRequired = true;
    _bindingUpserts.clear();
    _bindingRemovals.clear();
    _uploadedAdditions.clear();
    _uploadedRemovals.clear();
    _bindingSalt = List.generate(
      32,
      (_) => _random.nextInt(256),
    ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    _lastUpload = 0;
    _dropped = 0;
    _nativeDroppedSeen = 0;
    _storageSuccesses = 0;
    _storageMaxDuration = 0;
    _notificationLocks.clear();
    _notificationLockDropped = 0;
    _notificationLockDirty = false;
    _notificationLockSnapshotTimer?.cancel();
    _notificationLockSnapshotTimer = null;
  }

  Future<Map<String, Object?>> status() async => {
    'enabled': enabled,
    'retainedEvents': _events.length,
    'queuedEvents': _eventsById.length - _uploaded.length,
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
    final header = <String, Object?>{
      'schemaVersion': 1,
      'runId': _runId,
      'status': await status(),
    };
    if (_testPersist == null && _storageHealthy && _directory != null) {
      try {
        return await _diagnosticPreviewFromFile(_file.path, header);
      } catch (_) {
        // Keep a report available when the optional disk archive is unavailable.
      }
    }
    return _encodeDiagnosticPreview({...header, 'events': _events.toList()});
  }

  Future<List<Map<String, Object?>>> eventsForTesting() async {
    await _persist();
    return _events.map((e) => Map<String, Object?>.from(e)).toList();
  }

  Future<void> flush() {
    if (_disposed || !_ready) return Future.value();
    final existing = _flushFuture;
    if (existing != null) {
      // Joining a network flush must still persist events admitted since its
      // snapshot, even when their regular write window has not elapsed yet.
      return Future.wait<void>([existing, _persist()]).then((_) {});
    }
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
      _prune();
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
            'queuedEvents': _eventsById.length - _uploaded.length,
            'droppedEvents': _dropped,
            'storageHealthy': _storageHealthy,
            'nativeHealthy': _nativeHealthy,
            'consentPending': _consentPending,
          },
        );
      }
      // Prioritize terminal observations without sorting/copying the backlog.
      final pending = _events.where((e) => !_uploaded.contains(e['eventId']));
      final terminal = pending.where((e) => e['stage'] == 'finish').take(64);
      final batch = terminal
          .followedBy(pending.where((e) => e['stage'] != 'finish'))
          .take(64)
          .map(_legacyRelayProjection)
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
          // An in-flight upload may finish after retention evicted its row.
          // Keep the acknowledgment index a subset of the retained archive.
          if (!_eventsById.containsKey(id)) {
            acknowledged++;
            continue;
          }
          if (_uploaded.add(id)) {
            _uploadedAdditions.add(id);
            _uploadedRemovals.remove(id);
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
      await _persist(force: true);
    } catch (_) {
      _backoff('bridge_unavailable');
    }
  }

  // A deployed v1 relay may predate lock observation vocabulary. Keep rich
  // operation/lifecycle evidence locally and in exports, while uploads retain
  // the old aggregate shape until receiver support is explicitly negotiated.
  // Preserve event identity so retries/ACKs still refer to the local record.
  static Map<String, Object?> _legacyRelayProjection(
    Map<String, Object?> event,
  ) {
    final projected = Map<String, Object?>.from(event);
    final values = event['values'];
    if (event['feature'] == 'push' &&
        event['stage'] == 'snapshot' &&
        values is Map &&
        values['operation'] == 'notification_flock') {
      projected['values'] = Map<String, Object?>.from(values)
        ..['operation'] = 'other'
        ..remove('appLifecycle');
    }
    return projected;
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
      await _persist(force: true);
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
    if (dropped != _nativeDroppedSeen) _writeRequested = true;
    _dropped += max(0, dropped - _nativeDroppedSeen);
    _nativeDroppedSeen = dropped;
    final ack = <String>[];
    for (final raw in (result['events'] as List).take(64)) {
      final event = validateEvent(raw);
      if (event != null &&
          (event['source'] == 'android' || event['source'] == 'ios')) {
        event['reportingRunId'] = _runId;
        if (!_eventsById.containsKey(event['eventId'])) _append(event);
        ack.add(event['eventId'] as String);
      } else {
        _dropped++;
        _writeRequested = true;
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
    () => _byteCounter.count(event),
  );

  String _groupKey(Map<String, Object?> event) =>
      (event['attemptId'] ?? event['traceId'] ?? event['runId']) as String;

  bool _append(Map<String, Object?> event, {int? encodedSize}) {
    final id = event['eventId'] as String;
    if (_eventsById.containsKey(id)) return true;
    if (_integer(event['occurredAtMs']) < _nowMs - _retentionMs) return false;
    _writeRequested = true;
    final key = _groupKey(event);
    final group = _groups[key] ?? _DiagnosticGroup();
    final incomingSize = encodedSize == null
        ? _eventSize(event)
        : (_eventSizes[id] = encodedSize);
    while (group.events.length >= 255 || group.bytes + incomingSize > 64000) {
      if (event['stage'] != 'finish' || group.events.isEmpty) {
        _dropped++;
        _eventSizes.remove(id);
        return false;
      }
      _removeEvent(group.events.values.first, countDropped: true);
    }
    _eventsById[id] = event;
    if (_ready) _archiveWriter?.stageEvent(event);
    final expiry = _integer(event['occurredAtMs']) + _retentionMs + 1;
    _nextEventExpiryMs = min(_nextEventExpiryMs ?? expiry, expiry);
    group.events[id] = event;
    group.bytes += incomingSize;
    _retainedBytes += incomingSize;
    // Access order matches the most recently admitted event in each attempt.
    // Admission touches only this group and any rows actually evicted, never
    // rescanning the retained archive on a message or media interaction.
    _groups.remove(key);
    _groups[key] = group;
    while (_groups.length > 100) {
      final oldest = _groups.values.first;
      for (final old in oldest.events.values.toList()) {
        _removeEvent(old, countDropped: true);
      }
    }
    while (_retainedBytes > _maxBytes - 128 * 1024) {
      _removeEvent(_events.first, countDropped: true);
    }
    return _eventsById.containsKey(id);
  }

  void _removeEvent(Map<String, Object?> event, {bool countDropped = false}) {
    final id = event['eventId'] as String;
    if (_eventsById.remove(id) == null) return;
    _archiveWriter?.removeEvent(id);
    final size = _eventSizes.remove(id) ?? 0;
    _retainedBytes -= size;
    if (_uploaded.remove(id)) {
      _uploadedAdditions.remove(id);
      _uploadedRemovals.add(id);
    } else if (countDropped) {
      _dropped++;
    }
    final key = _groupKey(event);
    final group = _groups[key]!;
    group.events.remove(id);
    group.bytes -= size;
    if (group.events.isEmpty) {
      _groups.remove(key);
      _finished.remove(key);
      _open.remove(key);
      _attempts.removeWhere((_, attempt) => attempt == key);
    }
  }

  void _removeBinding(String key) {
    if (_bindings.remove(key) == null) return;
    _bindingTimes.remove(key);
    _bindingUpserts.remove(key);
    _bindingRemovals.add(key);
  }

  void _prune() {
    final cutoff = _nowMs - _retentionMs;
    if (_nextBindingExpiryMs case final expiry? when _nowMs >= expiry) {
      _nextBindingExpiryMs = null;
      final expiredBindings = <String>[];
      for (final entry in _bindingTimes.entries) {
        if (entry.value < cutoff) {
          expiredBindings.add(entry.key);
        } else {
          final next = entry.value + _retentionMs + 1;
          _nextBindingExpiryMs = min(_nextBindingExpiryMs ?? next, next);
        }
      }
      for (final key in expiredBindings) {
        _removeBinding(key);
        _writeRequested = true;
      }
    }
    // Do not walk a near-full archive every second when nothing can expire.
    // Recompute the deadline only when the earliest possible expiry is due.
    if (_nextEventExpiryMs case final expiry? when _nowMs >= expiry) {
      _nextEventExpiryMs = null;
      for (final event in _events.toList()) {
        final at = _integer(event['occurredAtMs']);
        if (at < cutoff) {
          _removeEvent(event);
          _writeRequested = true;
        } else {
          final next = at + _retentionMs + 1;
          _nextEventExpiryMs = min(_nextEventExpiryMs ?? next, next);
        }
      }
    }
    _finished.removeWhere((id) => !_groups.containsKey(id));
    _open.removeWhere((id, _) => !_groups.containsKey(id));
    _attempts.removeWhere((_, id) => !_groups.containsKey(id));
  }

  void _schedulePersist() {
    if (_directory == null || !_ready || _disposed) return;
    _writeRequested = true;
    // A fixed window (not a sliding debounce) also bounds loss on termination
    // during a sustained burst. Explicit flush/consent/lifecycle bypass it.
    _persistTimer ??= Timer(const Duration(seconds: 1), () {
      _persistTimer = null;
      unawaited(_persist());
    });
  }

  Future<void> _persist({bool force = false}) {
    if (_directory == null || !_ready || _disposed) return Future.value();
    _persistTimer?.cancel();
    _persistTimer = null;
    if (force) _writeRequested = true;
    _prune();
    final active = _writing;
    if (active != null) {
      if (_writeRequested) _urgentWriteRequested = true;
      return active;
    }
    if (!_writeRequested) return Future.value();
    final completed = Completer<void>();
    _writing = completed.future;
    unawaited(() async {
      while (_writeRequested &&
          (_persistTimer == null || _urgentWriteRequested) &&
          !_disposed) {
        try {
          _persistTimer?.cancel();
          _persistTimer = null;
          _urgentWriteRequested = false;
          _prune();
          _writeRequested = false;
          final fullMetadata = _fullMetadataRequired || _testPersist != null;
          final snapshot = <String, Object?>{
            'schemaVersion': 1,
            'enabled': enabled,
            'consentEpoch': _epoch,
            'clearPending': _clearPending,
            'nativeClearPending': _nativeClearPending,
            'dropped': _dropped,
            'nativeDroppedSeen': _nativeDroppedSeen,
            'lastUploadAtMs': _lastUpload,
            'bindingSalt': _bindingSalt,
            if (fullMetadata)
              'bindings': {
                for (final entry in _bindings.entries)
                  entry.key: {
                    'traceId': entry.value,
                    'updatedAtMs': _bindingTimes[entry.key],
                  },
              },
            if (fullMetadata) 'uploaded': _uploaded.toList(),
            'open': _open.values.toList(),
          };
          final Future<void> write;
          if (_testPersist case final persist?) {
            write = persist(_file.path, {
              ...snapshot,
              'events': _events.toList(),
            });
          } else {
            write = _archiveWriter!.persist(
              snapshot,
              metadataDelta: fullMetadata
                  ? null
                  : DiagnosticArchiveMetadataDelta(
                      mapUpserts: {'bindings': _bindingUpserts},
                      mapRemovals: {'bindings': _bindingRemovals.toList()},
                      setAdditions: {'uploaded': _uploadedAdditions.toList()},
                      setRemovals: {'uploaded': _uploadedRemovals.toList()},
                    ),
            );
          }
          // persist detaches both row and metadata deltas before its first
          // await. New mutations stay pending while the worker commits; an IO
          // retry retains the worker's already merged state. Clear requests a
          // full replacement so no old binding or acknowledgment can return.
          _fullMetadataRequired = false;
          _bindingUpserts.clear();
          _bindingRemovals.clear();
          _uploadedAdditions.clear();
          _uploadedRemovals.clear();
          await write;
        } catch (_) {
          _fullMetadataRequired = true;
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

  void _observeNotificationFileLock(
    Object owner,
    NotificationFileLockPhase phase,
  ) {
    if (!enabled || !_ready) return;
    final existing = _notificationLocks[owner];
    switch (phase) {
      case NotificationFileLockPhase.waiting:
        if (existing != null) return;
        if (_notificationLocks.length >= _maxObservedNotificationLocks) {
          _notificationLockDropped = min(
            _notificationLockDropped + 1,
            1000000000,
          );
        } else {
          _notificationLocks[owner] = _NotificationFileLockObservation(
            phase,
            _elapsed.elapsedMilliseconds,
          );
        }
      case NotificationFileLockPhase.held:
        if (existing == null) return;
        existing.phase = phase;
        existing.startedMs = _elapsed.elapsedMilliseconds;
      case NotificationFileLockPhase.released:
        if (existing == null) return;
        _notificationLocks.remove(owner);
    }
    _notificationLockDirty = true;
    // No event construction or persistence on an acquisition's critical path.
    // While inactive, one isolate-local timer coalesces all owner changes.
    if (_notificationLockInactive && _notificationLockSnapshotTimer == null) {
      _notificationLockSnapshotTimer = Timer(const Duration(seconds: 1), () {
        _notificationLockSnapshotTimer = null;
        _recordNotificationFileLockSnapshot();
      });
    }
  }

  void _recordNotificationFileLockSnapshot() {
    if (!_notificationLockDirty && _notificationLocks.isEmpty) return;
    _notificationLockDirty = false;
    var held = 0;
    var waiting = 0;
    var oldestMs = 0;
    for (final owner in _notificationLocks.values) {
      if (owner.phase == NotificationFileLockPhase.held) {
        held++;
      } else {
        waiting++;
      }
      oldestMs = max(oldestMs, _elapsed.elapsedMilliseconds - owner.startedMs);
    }
    // The existing closed schema represents this fixed snapshot kind. Counts
    // cover this Dart isolate's notification flock helper, not SQLite/Go/NSE.
    // Dropped owners explicitly make the observation incomplete. This is a
    // sampled breadcrumb, never proof of which lock caused an OS termination.
    // cleanupComplete describes only owners observed since this collector was
    // enabled; it cannot clear owners begun while disabled or before install.
    record(
      feature: 'push',
      stage: 'snapshot',
      outcome: _notificationLockDropped > 0
          ? 'unknown'
          : held + waiting > 0
          ? 'pending'
          : 'ok',
      reason: _notificationLockDropped > 0 ? 'quota_exceeded' : 'none',
      values: {
        'operation': 'notification_flock',
        'appLifecycle': _notificationLockLifecycle?.name ?? 'unknown',
        'count': held,
        'queuedEvents': waiting,
        'durationMs': oldestMs,
        'droppedEvents': _notificationLockDropped,
        'cleanupComplete': held + waiting == 0 && _notificationLockDropped == 0,
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _notificationLockLifecycle = state;
    _notificationLockInactive = state != AppLifecycleState.resumed;
    _notificationLockSnapshotTimer?.cancel();
    _notificationLockSnapshotTimer = null;
    _recordNotificationFileLockSnapshot();
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
    _persistTimer?.cancel();
    _notificationLockSnapshotTimer?.cancel();
    if (identical(AppDiagnosticEvents.onStorageTransaction, _storageObserver)) {
      AppDiagnosticEvents.onStorageTransaction = null;
    }
    if (identical(
      AppDiagnosticEvents.onNotificationFileLock,
      _notificationLockObserver,
    )) {
      AppDiagnosticEvents.onNotificationFileLock = null;
    }
    _notificationLocks.clear();
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    await _flushFuture;
    await _persist();
    _disposed = true;
    await _archiveWriter?.dispose();
  }

  static int _integer(Object? value) =>
      value is int && value >= 0 && value <= 9007199254740991 ? value : 0;
  static bool _closed(String field, Object? value) =>
      _closedFields[field]?.contains(value) ?? false;

  static Map<String, Object?>? validateEvent(Object? raw) =>
      _validateEventAndSize(raw)?.event;

  static ({Map<String, Object?> event, int bytes})? _validateEventAndSize(
    Object? raw,
  ) {
    if (raw is! Map || raw['schemaVersion'] != 1) return null;
    try {
      if (raw.keys.any((k) => !_allowedFields.contains(k))) return null;
      if ((appDiagnosticSchemaV1['required'] as List).any(
        (k) => !raw.containsKey(k),
      )) {
        return null;
      }
      for (final key in appDiagnosticSchemaV1['uuidFields'] as List) {
        if (raw.containsKey(key) && !isValidTraceId(raw[key])) return null;
      }
      for (final key in const [
        'source',
        'platform',
        'feature',
        'stage',
        'outcome',
        'reason',
      ]) {
        if (!_closed(key, raw[key])) return null;
      }
      for (final key in const ['sequence', 'occurredAtMs', 'elapsedMs']) {
        if (raw[key] is! int || _integer(raw[key]) != raw[key]) return null;
      }
      if (raw['build'] is! String ||
          !_buildPattern.hasMatch(raw['build'] as String)) {
        return null;
      }
      final values = raw['values'];
      if (values is! Map || values.length > 16) return null;
      for (final entry in values.entries) {
        if (_closed('booleanValues', entry.key)) {
          if (entry.value is! bool) return null;
        } else if (_closed('integerValues', entry.key)) {
          if (entry.value is! int || _integer(entry.value) != entry.value) {
            return null;
          }
        } else if (_closed('hashValues', entry.key)) {
          if (entry.value is! String ||
              !_hashPattern.hasMatch(entry.value as String)) {
            return null;
          }
        } else {
          if (!(_valueEnums[entry.key]?.contains(entry.value) ?? false)) {
            return null;
          }
        }
      }
      final bytes = _byteCounter.count(raw);
      if (bytes > 4096) return null;
      final event = Map<String, Object?>.from(raw);
      event['values'] = Map<String, Object?>.from(values);
      return (event: event, bytes: bytes);
    } catch (_) {
      return null;
    }
  }
}
