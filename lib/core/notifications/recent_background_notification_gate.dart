import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'package:flutter_app/core/utils/flow_event_emitter.dart';

const Duration recentBackgroundNotificationTtl = Duration(hours: 12);

const String _recentBackgroundNotificationFileName =
    'mknoon_recent_background_notifications.json';

RecentBackgroundNotificationGate recentBackgroundNotificationGate =
    RecentBackgroundNotificationGate();

@visibleForTesting
void debugSetRecentBackgroundNotificationGate(
  RecentBackgroundNotificationGate gate,
) {
  recentBackgroundNotificationGate = gate;
}

@visibleForTesting
void debugResetRecentBackgroundNotificationGate() {
  recentBackgroundNotificationGate = RecentBackgroundNotificationGate();
}

void _defaultRecentBackgroundGateLoadError(Object error, StackTrace stack) {
  // 04-P0 / QW-3: surface a wiped/corrupt gate file instead of silently
  // treating it as "no entries" (which bypasses the 12h redelivery guard).
  emitFlowEvent(
    layer: 'FL',
    event: 'RECENT_BACKGROUND_NOTIFICATION_GATE_DECODE_ERROR',
    details: {'error': error.runtimeType.toString()},
  );
}

class RecentBackgroundNotificationGate {
  final String? _explicitFilePath;
  final Duration ttl;
  final DateTime Function() _now;
  final Future<Directory> Function() _supportDirectoryProvider;
  final void Function(Object error, StackTrace stack) _onLoadError;

  Future<String>? _resolvedPathFuture;

  RecentBackgroundNotificationGate({
    String? filePath,
    Duration? ttl,
    DateTime Function()? now,
    Future<Directory> Function()? supportDirectoryProvider,
    void Function(Object error, StackTrace stack)? onLoadError,
  }) : _explicitFilePath = filePath,
       ttl = ttl ?? recentBackgroundNotificationTtl,
       _now = now ?? DateTime.now,
       _supportDirectoryProvider =
           supportDirectoryProvider ?? getApplicationSupportDirectory,
       _onLoadError = onLoadError ?? _defaultRecentBackgroundGateLoadError;

  /// Synchronous view of the configured path. When an explicit [filePath] was
  /// provided (every test does) it is returned verbatim; otherwise the durable
  /// app-support path is resolved lazily on first IO and this returns the
  /// systemTemp fallback name. IO uses the lazily-resolved [resolveFilePath].
  String get filePath =>
      _explicitFilePath ??
      '${Directory.systemTemp.path}/$_recentBackgroundNotificationFileName';

  @visibleForTesting
  Future<String> resolveFilePath() => _resolveFilePath();

  Future<String> _resolveFilePath() {
    return _resolvedPathFuture ??= _doResolveFilePath();
  }

  Future<String> _doResolveFilePath() async {
    final explicit = _explicitFilePath;
    if (explicit != null) {
      return explicit;
    }
    try {
      final dir = await _supportDirectoryProvider();
      return '${dir.path}/$_recentBackgroundNotificationFileName';
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'RECENT_BACKGROUND_NOTIFICATION_GATE_DIR_FALLBACK',
        details: {'error': error.runtimeType.toString()},
      );
      return '${Directory.systemTemp.path}/$_recentBackgroundNotificationFileName';
    }
  }

  Future<void> markShown(String key) async {
    final normalizedKey = _normalizeKey(key);
    if (normalizedKey == null) {
      return;
    }

    final entries = await _loadEntries();
    entries[normalizedKey] = _now().millisecondsSinceEpoch;
    await _writeEntries(entries);
  }

  Future<bool> wasRecentlyShown(String key) async {
    final normalizedKey = _normalizeKey(key);
    if (normalizedKey == null) {
      return false;
    }

    final entries = await _loadEntries();
    return entries.containsKey(normalizedKey);
  }

  Future<void> clear() async {
    try {
      final file = File(await _resolveFilePath());
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  Future<Map<String, int>> _loadEntries() async {
    try {
      final file = File(await _resolveFilePath());
      if (!await file.exists()) {
        return <String, int>{};
      }

      final raw = await file.readAsString();
      if (raw.trim().isEmpty) {
        return <String, int>{};
      }

      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        _onLoadError(
          const FormatException(
            'recent-background notification gate payload is not a JSON object',
          ),
          StackTrace.current,
        );
        return <String, int>{};
      }

      final cutoff = _now().millisecondsSinceEpoch - ttl.inMilliseconds;
      final entries = <String, int>{};
      for (final entry in decoded.entries) {
        final key = _normalizeKey(entry.key);
        final timestamp = _coerceTimestamp(entry.value);
        if (key == null || timestamp == null || timestamp < cutoff) {
          continue;
        }
        entries[key] = timestamp;
      }
      return entries;
    } catch (error, stack) {
      _onLoadError(error, stack);
      return <String, int>{};
    }
  }

  Future<void> _writeEntries(Map<String, int> entries) async {
    try {
      final file = File(await _resolveFilePath());
      if (entries.isEmpty) {
        if (await file.exists()) {
          await file.delete();
        }
        return;
      }

      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(entries), flush: true);
    } catch (_) {}
  }

  static String? _normalizeKey(String? key) {
    final normalized = key?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  static int? _coerceTimestamp(Object? rawValue) {
    if (rawValue is int) {
      return rawValue;
    }
    if (rawValue is num) {
      return rawValue.toInt();
    }
    if (rawValue is String) {
      return int.tryParse(rawValue);
    }
    return null;
  }
}
