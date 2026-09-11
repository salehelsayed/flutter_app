import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

typedef DiagnosticArchiveEventValidator =
    Map<String, Object?>? Function(Object? event);

/// Changes to metadata collections whose retained entries remain in the worker.
/// Map values are JSON values; set fields are lists of unique strings.
/// Removals precede upserts/additions when the same member appears in both.
final class DiagnosticArchiveMetadataDelta {
  const DiagnosticArchiveMetadataDelta({
    this.mapUpserts = const {},
    this.mapRemovals = const {},
    this.setAdditions = const {},
    this.setRemovals = const {},
  });

  final Map<String, Map<String, Object?>> mapUpserts;
  final Map<String, List<String>> mapRemovals;
  final Map<String, List<String>> setAdditions;
  final Map<String, List<String>> setRemovals;

  List<Object?> _snapshot() {
    final mapFields = {...mapUpserts.keys, ...mapRemovals.keys};
    final setFields = {...setAdditions.keys, ...setRemovals.keys};
    if (mapFields.contains('events') || setFields.contains('events')) {
      throw ArgumentError('Metadata deltas must not contain event history');
    }
    if (mapFields.any(setFields.contains)) {
      throw ArgumentError('A metadata field cannot be both a map and a set');
    }
    return [
      _copyJson(mapUpserts),
      _copyJson(mapRemovals),
      _copyJson(setAdditions),
      _copyJson(setRemovals),
    ];
  }
}

/// Counts default JSON UTF-8 bytes without allocating an encoded event buffer.
/// Accepts JSON primitives, lists and string-keyed maps, without calling toJson.
/// This measures already validated data; it does not perform privacy validation.
final class DiagnosticJsonByteCounter {
  DiagnosticJsonByteCounter({Iterable<String> cachedStrings = const []})
    : _cachedStringBytes = {
        for (final value in cachedStrings) value: _stringBytes(value),
      };

  // Only caller-supplied schema strings are cached. Runtime identifiers and
  // arbitrary strings never expand the cache during count().
  final Map<String, int> _cachedStringBytes;

  int get cachedStringCount => _cachedStringBytes.length;

  int count(Object? value) => _count(value, <Object>[]);

  int _count(Object? value, List<Object> active) {
    if (value is String) {
      return _cachedStringBytes[value] ?? _stringBytes(value);
    }
    if (value is int) return _integerBytes(value);
    if (value is double) {
      if (!value.isFinite) throw JsonUnsupportedObjectError(value);
      // Dart's JSON encoder uses the same canonical ASCII representation.
      return value.toString().length;
    }
    if (value == null || identical(value, true)) return 4;
    if (identical(value, false)) return 5;
    if (value is! List && value is! Map) {
      throw JsonUnsupportedObjectError(value);
    }
    for (final ancestor in active) {
      if (identical(ancestor, value)) throw JsonCyclicError(value);
    }
    active.add(value);
    try {
      var bytes = 2; // Container delimiters.
      if (value is List) {
        if (value.isNotEmpty) bytes += value.length - 1;
        for (final item in value) {
          bytes += _count(item, active);
        }
      } else {
        final map = value as Map;
        if (map.isNotEmpty) bytes += map.length - 1;
        map.forEach((Object? key, Object? item) {
          if (key is! String) throw JsonUnsupportedObjectError(map);
          bytes += (_cachedStringBytes[key] ?? _stringBytes(key)) + 1;
          bytes += _count(item, active);
        });
      }
      return bytes;
    } finally {
      active.removeLast();
    }
  }

  static int _integerBytes(int value) {
    var bytes = 1;
    if (value < 0) {
      bytes++;
      value = -value;
      // Negation of the minimum native 64-bit integer wraps to itself.
      if (value < 0) return 20;
    }
    if (value >= 10000000000000000) {
      bytes += 16;
      value ~/= 10000000000000000;
    }
    if (value >= 100000000) {
      bytes += 8;
      value ~/= 100000000;
    }
    if (value >= 10000) {
      bytes += 4;
      value ~/= 10000;
    }
    if (value >= 100) {
      bytes += 2;
      value ~/= 100;
    }
    if (value >= 10) bytes++;
    return bytes;
  }

  static int _stringBytes(String value) {
    var bytes = 2; // Quotes.
    for (var index = 0; index < value.length; index++) {
      final code = value.codeUnitAt(index);
      if (code < 0x20) {
        bytes += switch (code) {
          0x08 || 0x09 || 0x0a || 0x0c || 0x0d => 2,
          _ => 6,
        };
      } else if (code == 0x22 || code == 0x5c) {
        bytes += 2;
      } else if (code < 0x80) {
        bytes++;
      } else if (code < 0x800) {
        bytes += 2;
      } else if (code >= 0xd800 && code <= 0xdfff) {
        if (code <= 0xdbff && index + 1 < value.length) {
          final next = value.codeUnitAt(index + 1);
          if (next >= 0xdc00 && next <= 0xdfff) {
            bytes += 4;
            index++;
            continue;
          }
        }
        bytes += 6; // The JSON encoder escapes unpaired UTF-16 surrogates.
      } else {
        bytes += 3;
      }
    }
    return bytes;
  }
}

/// Keeps the archive in a persistent worker; only changed rows cross isolates.
/// The caller owns collection, consent, validation and retention decisions.
final class DiagnosticArchiveWriter {
  /// [validateEvent] must be a static or top-level function; it is transferred
  /// once at startup without capturing application objects or archive history.
  DiagnosticArchiveWriter(
    this._path, {
    DiagnosticArchiveEventValidator? validateEvent,
  }) : _validateEvent = validateEvent;

  final String _path;
  final DiagnosticArchiveEventValidator? _validateEvent;
  Map<String, Map<String, Object?>> _upserts = {};
  Set<String> _removals = {};
  final Set<String> _knownIds = {};
  Set<String>? _initialRetainedIds = {};
  bool _clearPending = false;
  bool _closing = false;
  bool _closed = false;
  Object? _failure;
  StackTrace? _failureStack;
  Future<void> _tail = Future<void>.value();
  Future<void>? _starting;
  Future<void>? _disposing;
  Isolate? _isolate;
  ReceivePort? _responses;
  SendPort? _commands;
  Completer<SendPort>? _ready;
  final Map<int, Completer<void>> _requests = {};
  int _sequence = 0;

  /// Supplies the parent's authoritative initial validation/retention result.
  /// The worker reads those rows privately from the existing archive once.
  void initializeRetainedEvents(Iterable<String> ids) {
    if (_initialRetainedIds == null || _closing || _closed) {
      throw StateError('Archive initialization must precede persistence');
    }
    _initialRetainedIds = ids.toSet();
    _knownIds
      ..clear()
      ..addAll(_initialRetainedIds!);
  }

  /// Snapshots the changed row, including mutable values or a rebound trace ID.
  void stageEvent(Map<String, Object?> event) {
    if (_closing || _closed || _failure != null) return;
    final id = event['eventId'];
    if (id is! String || id.isEmpty) {
      throw ArgumentError('A diagnostic event requires an eventId');
    }
    _upserts[id] = _copyJson(event) as Map<String, Object?>;
    _removals.remove(id);
  }

  void removeEvent(String id) {
    if (_closing || _closed || _failure != null) return;
    _upserts.remove(id);
    // A row evicted before its first snapshot never existed in the worker.
    if (_knownIds.contains(id)) _removals.add(id);
  }

  void clearEvents() {
    if (_closing || _closed || _failure != null) return;
    _upserts.clear();
    _removals.clear();
    _knownIds.clear();
    _clearPending = true;
  }

  /// Detaches deltas before any await, including before lazy worker startup.
  /// Requests remain FIFO even if a caller queues the next write immediately.
  /// Without [metadataDelta], metadata replaces every previously supplied field.
  /// With a delta, supplied fields replace only those fields, followed by the
  /// collection changes. The first commit must supply full sanitized metadata.
  Future<void> persist(
    Map<String, Object?> metadata, {
    DiagnosticArchiveMetadataDelta? metadataDelta,
  }) {
    if (_failure != null) {
      return Future<void>.error(_failure!, _failureStack);
    }
    if (_closing || _closed) {
      return Future<void>.error(StateError('Diagnostic archive is disposed'));
    }
    if (metadata.containsKey('events')) {
      return Future<void>.error(
        ArgumentError('Archive metadata must not contain event history'),
      );
    }
    final Object? detachedMetadata;
    final List<Object?>? detachedMetadataDelta;
    try {
      detachedMetadata = _copyJson(metadata);
      detachedMetadataDelta = metadataDelta?._snapshot();
    } catch (error, stack) {
      return Future<void>.error(error, stack);
    }
    final upserts = _upserts;
    final removals = _removals;
    final clear = _clearPending;
    final retainedIds = _initialRetainedIds?.toList(growable: false);
    _upserts = {};
    _removals = {};
    _clearPending = false;
    _initialRetainedIds = null;
    if (clear) _knownIds.clear();
    _knownIds
      ..removeAll(removals)
      ..addAll(upserts.keys);
    final message = <Object?>[
      ++_sequence,
      detachedMetadata,
      upserts.values.toList(growable: false),
      removals.toList(growable: false),
      clear,
      retainedIds,
      detachedMetadataDelta,
    ];
    final result = _tail.then((_) => _write(message));
    // Observe failure independently of the caller so an optional background
    // sink can never raise an unhandled asynchronous application error.
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> _write(List<Object?> message) async {
    await _ensureWorker();
    if (_failure != null) {
      Error.throwWithStackTrace(_failure!, _failureStack ?? StackTrace.current);
    }
    final completion = Completer<void>();
    completion.future.ignore();
    _requests[message[0] as int] = completion;
    try {
      _commands!.send(message);
    } catch (error, stack) {
      _fail(error, stack);
    }
    await completion.future;
  }

  Future<void> _ensureWorker() {
    if (_failure != null) {
      return Future<void>.error(_failure!, _failureStack);
    }
    return _starting ??= _startWorker();
  }

  Future<void> _startWorker() async {
    final responses = ReceivePort();
    final ready = Completer<SendPort>();
    ready.future.ignore();
    _responses = responses;
    _ready = ready;
    responses.listen((message) {
      if (message is SendPort) {
        if (!ready.isCompleted) ready.complete(message);
      } else if (message is List && message.length >= 2 && message[0] is int) {
        if (message[1] == true) {
          _requests.remove(message[0])?.complete();
        } else {
          final error = StateError(
            'Diagnostic archive write failed (${message[2]})',
          );
          if (message.length > 3 && message[3] == true) {
            // The worker applied this delta but disk persistence failed. Its
            // retained state still matches our IDs; a later FIFO commit can
            // retry it without transferring or rebuilding the archive.
            _requests.remove(message[0])?.completeError(error);
          } else {
            _fail(error, StackTrace.current);
          }
        }
      } else {
        // onError and onExit share this port. Never forward remote raw error
        // text or let an isolate exit strand an awaiting application future.
        _fail(
          StateError('Diagnostic archive worker exited'),
          StackTrace.current,
        );
      }
    });
    try {
      final isolate = await Isolate.spawn<List<Object?>>(
        _runDiagnosticArchiveWriter,
        <Object?>[_path, responses.sendPort, _validateEvent],
        onError: responses.sendPort,
        onExit: responses.sendPort,
        errorsAreFatal: true,
        debugName: 'diagnostic-archive',
      );
      if (_failure != null || _closed) {
        isolate.kill(priority: Isolate.immediate);
        throw _failure ?? StateError('Diagnostic archive is disposed');
      }
      _isolate = isolate;
      _commands = await ready.future;
    } catch (error, stack) {
      _fail(error, stack);
      rethrow;
    }
  }

  void _fail(Object error, StackTrace stack) {
    _failure ??= error;
    _failureStack ??= stack;
    final ready = _ready;
    if (ready != null && !ready.isCompleted) {
      ready.completeError(_failure!, _failureStack);
    }
    for (final completion in _requests.values) {
      completion.completeError(_failure!, _failureStack);
    }
    _requests.clear();
    _stopWorker();
    _upserts.clear();
    _removals.clear();
    _knownIds.clear();
  }

  /// Finishes already requested writes, then releases the isolate and ports.
  Future<void> dispose() {
    if (_disposing != null) return _disposing!;
    _closing = true;
    return _disposing = _tail.then((_) {
      _closed = true;
      _stopWorker();
      _upserts.clear();
      _removals.clear();
      _knownIds.clear();
    });
  }

  void _stopWorker() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _responses?.close();
    _responses = null;
    _commands = null;
  }
}

Object? _copyJson(Object? value) {
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        entry.key as String: _copyJson(entry.value),
    };
  }
  if (value is List) return value.map(_copyJson).toList(growable: false);
  return value;
}

sealed class _DiagnosticMetadataValue {
  Iterable<List<int>> get fragments;
}

final class _DiagnosticMetadataScalar extends _DiagnosticMetadataValue {
  _DiagnosticMetadataScalar(this.bytes);
  final List<int> bytes;

  @override
  Iterable<List<int>> get fragments sync* {
    yield bytes;
  }
}

final class _DiagnosticMetadataMember {
  _DiagnosticMetadataMember(this.key, this.value);
  final List<int> key;
  _DiagnosticMetadataValue value;

  Iterable<List<int>> get fragments sync* {
    yield key;
    yield const <int>[58]; // :
    yield* value.fragments;
  }
}

final class _DiagnosticMetadataMap extends _DiagnosticMetadataValue {
  final entries = <String, _DiagnosticMetadataMember>{};

  @override
  Iterable<List<int>> get fragments sync* {
    yield const <int>[123]; // {
    var first = true;
    for (final member in entries.values) {
      if (!first) yield const <int>[44];
      yield* member.fragments;
      first = false;
    }
    yield const <int>[125]; // }
  }
}

final class _DiagnosticMetadataSet extends _DiagnosticMetadataValue {
  final entries = <String, List<int>>{};

  @override
  Iterable<List<int>> get fragments sync* {
    yield const <int>[91]; // [
    var first = true;
    for (final bytes in entries.values) {
      if (!first) yield const <int>[44];
      yield bytes;
      first = false;
    }
    yield const <int>[93]; // ]
  }
}

/// Unchanged rows retain their encoded representation between atomic commits.
/// Keeping bytes rather than row maps also releases the parsed startup objects.
final class _DiagnosticArchiveEncoder {
  static const _eventsPrefix = <int>[
    34,
    101,
    118,
    101,
    110,
    116,
    115,
    34,
    58,
    91,
  ];
  static const _comma = <int>[44];
  static const _closing = <int>[93, 125];
  final _json = JsonUtf8Encoder();
  final _events = <String, List<int>>{};
  final _metadata = <String, _DiagnosticMetadataMember>{};
  bool _metadataInitialized = false;
  final _writeBuffer = Uint8List(64 * 1024);

  void retainIfAbsent(Map<String, Object?> event) {
    if (!_events.containsKey(event['eventId'])) upsert(event);
  }

  void upsert(Map<String, Object?> event) {
    final id = event['eventId'] as String;
    _events[id] = _json.convert(event);
  }

  void remove(String id) {
    _events.remove(id);
  }

  void clear() {
    _events.clear();
  }

  _DiagnosticMetadataMember _member(
    String key,
    _DiagnosticMetadataValue value,
  ) => _DiagnosticMetadataMember(_json.convert(key), value);

  _DiagnosticMetadataValue _metadataValue(Object? value) {
    if (value is Map) {
      final cached = _DiagnosticMetadataMap();
      value.forEach((Object? key, Object? item) {
        cached.entries[key as String] = _member(
          key,
          _DiagnosticMetadataScalar(_json.convert(item)),
        );
      });
      return cached;
    }
    if (value is List && value.every((item) => item is String)) {
      final unique = value.toSet();
      if (unique.length == value.length) {
        final cached = _DiagnosticMetadataSet();
        for (final item in value.cast<String>()) {
          cached.entries[item] = _json.convert(item);
        }
        return cached;
      }
    }
    // Full replacements preserve arbitrary JSON lists, including duplicates.
    return _DiagnosticMetadataScalar(_json.convert(value));
  }

  _DiagnosticMetadataMap _mapField(String key) {
    final field = _metadata.putIfAbsent(
      key,
      () => _member(key, _DiagnosticMetadataMap()),
    );
    if (field.value is! _DiagnosticMetadataMap) {
      throw StateError('Metadata map delta requires a map field');
    }
    return field.value as _DiagnosticMetadataMap;
  }

  _DiagnosticMetadataSet _setField(String key) {
    final field = _metadata.putIfAbsent(
      key,
      () => _member(key, _DiagnosticMetadataSet()),
    );
    if (field.value is! _DiagnosticMetadataSet) {
      throw StateError('Metadata set delta requires a unique string list');
    }
    return field.value as _DiagnosticMetadataSet;
  }

  void applyMetadata(Map<String, Object?> metadata, List? delta) {
    if (delta != null && !_metadataInitialized) {
      throw StateError('The first metadata commit must be a full replacement');
    }
    if (delta == null) _metadata.clear();
    metadata.forEach((key, value) {
      final encoded = _metadataValue(value);
      final existing = _metadata[key];
      if (existing != null) {
        existing.value = encoded;
      } else {
        _metadata[key] = _member(key, encoded);
      }
    });
    if (delta != null) {
      final mapUpserts = delta[0] as Map;
      final mapRemovals = delta[1] as Map;
      final setAdditions = delta[2] as Map;
      final setRemovals = delta[3] as Map;
      mapRemovals.forEach((Object? key, Object? removals) {
        final field = _mapField(key as String);
        for (final removed in removals as List) {
          field.entries.remove(removed as String);
        }
      });
      mapUpserts.forEach((Object? key, Object? upserts) {
        final field = _mapField(key as String);
        (upserts as Map).forEach((Object? name, Object? value) {
          final encoded = _DiagnosticMetadataScalar(_json.convert(value));
          final existing = field.entries[name];
          if (existing != null) {
            existing.value = encoded;
          } else {
            field.entries[name as String] = _member(name, encoded);
          }
        });
      });
      setRemovals.forEach((Object? key, Object? removals) {
        final field = _setField(key as String);
        for (final removed in removals as List) {
          field.entries.remove(removed as String);
        }
      });
      setAdditions.forEach((Object? key, Object? additions) {
        final field = _setField(key as String);
        for (final added in (additions as List).cast<String>()) {
          field.entries.putIfAbsent(added, () => _json.convert(added));
        }
      });
    }
    _metadataInitialized = true;
  }

  Iterable<List<int>> _fragments() sync* {
    yield const <int>[123]; // {
    for (final member in _metadata.values) {
      yield* member.fragments;
      yield _comma;
    }
    yield _eventsPrefix;
    var first = true;
    for (final event in _events.values) {
      if (!first) yield _comma;
      yield event;
      first = false;
    }
    yield _closing;
  }

  Future<void> writeTo(RandomAccessFile sink) async {
    var buffered = 0;
    for (final fragment in _fragments()) {
      final length = fragment.length;
      var offset = 0;
      while (offset < length) {
        final remaining = length - offset;
        final available = _writeBuffer.length - buffered;
        final count = remaining < available ? remaining : available;
        _writeBuffer.setRange(buffered, buffered + count, fragment, offset);
        buffered += count;
        offset += count;
        if (buffered == _writeBuffer.length) {
          // The same bounded storage is reused only after the write completes.
          // Small fragments share writes; large fragments span multiple writes.
          await sink.writeFrom(_writeBuffer, 0, buffered);
          buffered = 0;
        }
      }
    }
    if (buffered != 0) await sink.writeFrom(_writeBuffer, 0, buffered);
  }
}

// Top-level entrypoint deliberately captures no application or event history.
Future<void> _runDiagnosticArchiveWriter(List<Object?> initialization) async {
  final file = File(initialization[0] as String);
  final responses = initialization[1] as SendPort;
  final validateEvent = initialization[2] as DiagnosticArchiveEventValidator?;
  final commands = ReceivePort();
  responses.send(commands.sendPort);
  final encoder = _DiagnosticArchiveEncoder();
  var loaded = false;
  await for (final raw in commands) {
    final message = raw as List;
    final id = message[0] as int;
    final temporary = File('${file.path}.tmp');
    var deltaApplied = false;
    RandomAccessFile? sink;
    try {
      final clear = message[4] == true;
      if (!loaded) {
        if (!clear && await file.exists()) {
          final state = jsonDecode(await file.readAsString()) as Map;
          final retainedIds = (message[5] as List).cast<String>().toSet();
          final storedRows = state['events'];
          for (final row
              in storedRows is List ? storedRows : const <Object?>[]) {
            final valid = validateEvent != null
                ? validateEvent(row)
                : row is Map
                ? Map<String, Object?>.from(row)
                : null;
            if (valid != null &&
                valid['eventId'] is String &&
                retainedIds.contains(valid['eventId'])) {
              // Match the parent's first-valid-row index. A rejected duplicate
              // must never overwrite its safe row when reopening the archive.
              encoder.retainIfAbsent(valid);
            }
          }
        }
        loaded = true;
      }
      if (clear) encoder.clear();
      for (final removed in message[3] as List) {
        encoder.remove(removed as String);
      }
      for (final row in message[2] as List) {
        final event = Map<String, Object?>.from(row as Map);
        encoder.upsert(event);
      }
      encoder.applyMetadata(
        Map<String, Object?>.from(message[1] as Map),
        message[6] as List?,
      );
      deltaApplied = true;
      sink = await temporary.open(mode: FileMode.write);
      await encoder.writeTo(sink);
      await sink.flush();
      await sink.close();
      sink = null;
      await temporary.rename(file.path);
      responses.send(<Object?>[id, true]);
    } catch (error) {
      try {
        await sink?.close();
      } catch (_) {
        // Keep the original failure while releasing the handle when possible.
      }
      try {
        if (await temporary.exists()) await temporary.delete();
      } catch (_) {
        // Failure cleanup remains observation-only too.
      }
      responses.send(<Object?>[
        id,
        false,
        error.runtimeType.toString(),
        deltaApplied,
      ]);
    }
  }
}
