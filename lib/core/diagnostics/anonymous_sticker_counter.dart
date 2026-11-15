import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';

/// Only completed UTC-day totals leave the phone. A random nonce belongs to
/// one frozen batch, never to a phone/account, and survives retry/restart.
final class AnonymousStickerCounter {
  AnonymousStickerCounter({
    required this.directory,
    required Iterable<String> stickerIds,
    required this.enabled,
    required this.now,
    required this.upload,
  }) : _ids = Set.unmodifiable(stickerIds);

  final Directory directory;
  final Set<String> _ids;
  final bool Function() enabled;
  final DateTime Function() now;
  final Future<bool> Function(Map<String, Object?>) upload;
  final _days = <String, Map<String, Object?>>{};
  Future<void> _writes = Future.value();
  Future<void>? _flushing;
  Timer? _writeTimer;
  bool _ready = false;
  bool _disposed = false;
  int _epoch = 0;
  DateTime? _retryAt;
  String? _lastPersisted;

  File get _file => File('${directory.path}/counts.json');
  String _day(DateTime value) =>
      value.toUtc().toIso8601String().substring(0, 10);
  DateTime? _parseDay(String value) => DateTime.tryParse('${value}T00:00:00Z');

  Future<void> initialize() async {
    try {
      if (await _file.exists() && await _file.length() <= 65536) {
        final state = jsonDecode(await _file.readAsString());
        final raw = state is Map ? state['days'] : state;
        if (state is Map && state['retryAt'] is String) {
          _retryAt = DateTime.tryParse(state['retryAt'] as String);
        }
        if (raw is List && raw.length <= 4) {
          for (final entry in raw) {
            if (entry is! Map ||
                entry['day'] is! String ||
                entry['nonce'] is! String ||
                entry['counts'] is! Map) {
              continue;
            }
            final day = entry['day'] as String;
            final parsed = _parseDay(day);
            final nonce = entry['nonce'] as String;
            if (parsed == null ||
                _day(parsed) != day ||
                !RegExp(
                  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
                ).hasMatch(nonce)) {
              continue;
            }
            final counts = <String, int>{};
            var total = 0;
            for (final id in _ids) {
              final count = (entry['counts'] as Map)[id];
              if (count is int && count > 0 && total + count <= 1000) {
                counts[id] = count;
                total += count;
              }
            }
            if (counts.isNotEmpty) {
              _days[day] = {'day': day, 'nonce': nonce, 'counts': counts};
            }
          }
        }
      }
      _ready = true;
      _prune();
      if (!enabled() || _days.isEmpty) {
        _days.clear();
        _retryAt = null;
      }
      await _persist();
    } catch (_) {
      // Optional counts must never affect a sticker send or app readiness.
      _ready = false;
      _days.clear();
      _retryAt = null;
    }
  }

  void _prune() {
    final today = _parseDay(_day(now()))!;
    _days.removeWhere((day, _) {
      final age = today.difference(_parseDay(day)!).inDays;
      return age < 0 || age > 3;
    });
  }

  void record(String stickerId) {
    if (!_ready || _disposed || !enabled() || !_ids.contains(stickerId)) return;
    _prune();
    final day = _day(now());
    final batch = _days.putIfAbsent(
      day,
      () => {'day': day, 'nonce': const Uuid().v4(), 'counts': <String, int>{}},
    );
    final counts = batch['counts'] as Map<String, int>;
    if (counts.values.fold<int>(0, (a, b) => a + b) >= 1000) return;
    counts.update(stickerId, (v) => v + 1, ifAbsent: () => 1);
    _writeTimer ??= Timer(const Duration(seconds: 1), () {
      _writeTimer = null;
      unawaited(_persist());
    });
  }

  Future<void> clear() {
    _epoch++;
    _days.clear();
    _retryAt = null;
    return _persist();
  }

  Future<void> flush() {
    if (!_ready || _disposed) return Future.value();
    return _flushing ??= _flush().whenComplete(() => _flushing = null);
  }

  Future<void> _flush() async {
    final epoch = _epoch;
    _prune();
    if (!enabled()) {
      await clear();
      return;
    }
    await _persist();
    if (!_ready ||
        _disposed ||
        epoch != _epoch ||
        !enabled() ||
        (_retryAt != null && now().isBefore(_retryAt!))) {
      return;
    }
    final today = _day(now());
    final completed =
        _days.keys.where((day) => day.compareTo(today) < 0).toList()..sort();
    for (final day in completed) {
      if (_disposed || epoch != _epoch || !enabled()) return;
      final batch = _days[day];
      if (batch == null) continue;
      final frozen = <String, Object?>{
        ...batch,
        'counts': Map<String, int>.of(batch['counts'] as Map<String, int>),
      };
      var accepted = false;
      try {
        accepted = await upload(frozen);
      } catch (_) {}
      if (_disposed || epoch != _epoch || !enabled()) return;
      if (!accepted) {
        _retryAt = now().add(const Duration(hours: 1));
        await _persist();
        return;
      }
      _days.remove(day);
      await _persist();
      if (!_ready) return;
    }
    _retryAt = null;
    await _persist();
  }

  Future<void> _persist() {
    // Serialize snapshots, including opt-out behind an in-flight write.
    final raw = jsonEncode({
      'days': _days.values.toList(),
      'retryAt': _retryAt?.toUtc().toIso8601String(),
    });
    return _writes = _writes.then((_) async {
      if (raw == _lastPersisted) return;
      try {
        await directory.create(recursive: true);
        final tmp = File('${_file.path}.tmp');
        await tmp.writeAsString(raw, flush: true);
        await tmp.rename(_file.path);
        _lastPersisted = raw;
      } catch (_) {
        _ready = false;
      }
    });
  }

  Future<void> dispose() async {
    _writeTimer?.cancel();
    await _flushing;
    await _persist();
    _disposed = true;
  }
}
