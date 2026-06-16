import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'package:flutter_app/core/utils/flow_event_emitter.dart';

const Duration recentRemoteNotificationTtl = Duration(seconds: 30);
const Duration recentRemoteNotificationMessageTtl = Duration(hours: 12);

const String _recentRemoteNotificationFileName =
    'mknoon_recent_remote_notifications.json';

RecentRemoteNotificationGate recentRemoteNotificationGate =
    RecentRemoteNotificationGate();

@visibleForTesting
void debugSetRecentRemoteNotificationGate(RecentRemoteNotificationGate gate) {
  recentRemoteNotificationGate = gate;
}

@visibleForTesting
void debugResetRecentRemoteNotificationGate() {
  recentRemoteNotificationGate = RecentRemoteNotificationGate();
}

void _defaultRecentRemoteGateLoadError(Object error, StackTrace stack) {
  // 04-P0 / QW-3: a wiped/corrupt gate file silently bypassed dedupe and the
  // 12h redelivery guard. Surface the decode failure instead of swallowing it.
  emitFlowEvent(
    layer: 'FL',
    event: 'RECENT_REMOTE_NOTIFICATION_GATE_DECODE_ERROR',
    details: {'error': error.runtimeType.toString()},
  );
}

class RecentRemoteNotificationGate {
  final String? _explicitFilePath;
  final Duration ttl;
  final Duration messageTtl;
  final DateTime Function() _now;
  final Future<Directory> Function() _supportDirectoryProvider;
  final void Function(Object error, StackTrace stack) _onLoadError;

  // 04-P0 / SI-4: resolve the durable path once and cache the Future so
  // concurrent _loadEntries/_writeEntries/clear calls never re-resolve (and
  // never double-hit the platform channel).
  Future<String>? _resolvedPathFuture;

  RecentRemoteNotificationGate({
    String? filePath,
    Duration? ttl,
    Duration? messageTtl,
    DateTime Function()? now,
    Future<Directory> Function()? supportDirectoryProvider,
    void Function(Object error, StackTrace stack)? onLoadError,
  }) : _explicitFilePath = filePath,
       ttl = ttl ?? recentRemoteNotificationTtl,
       messageTtl = messageTtl ?? recentRemoteNotificationMessageTtl,
       _now = now ?? DateTime.now,
       _supportDirectoryProvider =
           supportDirectoryProvider ?? getApplicationSupportDirectory,
       _onLoadError = onLoadError ?? _defaultRecentRemoteGateLoadError;

  /// Synchronous view of the configured path. When an explicit [filePath] was
  /// provided (every test does) it is returned verbatim; otherwise the durable
  /// app-support path is resolved lazily on first IO and this returns the
  /// systemTemp fallback name. No production code reads this getter — IO uses
  /// the lazily-resolved path via [resolveFilePath].
  String get filePath =>
      _explicitFilePath ??
      '${Directory.systemTemp.path}/$_recentRemoteNotificationFileName';

  @visibleForTesting
  Future<String> resolveFilePath() => _resolveFilePath();

  Future<String> _resolveFilePath() {
    return _resolvedPathFuture ??= _doResolveFilePath();
  }

  Future<String> _doResolveFilePath() async {
    final explicit = _explicitFilePath;
    if (explicit != null) {
      // Explicit path short-circuits before any platform-channel await so
      // tests (and the per-test isolation bootstrap) stay synchronous-pathed.
      return explicit;
    }
    try {
      final dir = await _supportDirectoryProvider();
      return '${dir.path}/$_recentRemoteNotificationFileName';
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'RECENT_REMOTE_NOTIFICATION_GATE_DIR_FALLBACK',
        details: {'error': error.runtimeType.toString()},
      );
      return '${Directory.systemTemp.path}/$_recentRemoteNotificationFileName';
    }
  }

  Future<void> markPayload(String payload) async {
    await markAnnouncement(payload: payload);
  }

  Future<void> markAnnouncement({
    required String payload,
    String? messageId,
  }) async {
    final normalizedPayload = _normalizePayload(payload);
    if (normalizedPayload == null) {
      return;
    }

    final entries = await _loadEntries();
    final timestamp = _now().millisecondsSinceEpoch;
    final normalizedMessageId = _normalizePayload(messageId);
    if (normalizedMessageId != null) {
      entries[_messageKey(normalizedPayload, normalizedMessageId)] = timestamp;
    } else {
      entries[_payloadKey(normalizedPayload)] = timestamp;
    }
    await _writeEntries(entries);
  }

  Future<bool> consumeIfRecentPayload(String payload) async {
    return consumeIfRecentAnnouncement(payload: payload);
  }

  Future<bool> consumeIfRecentAnnouncement({
    required String payload,
    String? messageId,
  }) async {
    final normalizedPayload = _normalizePayload(payload);
    if (normalizedPayload == null) {
      return false;
    }

    final entries = await _loadEntries();
    final normalizedMessageId = _normalizePayload(messageId);
    int? timestamp;
    if (normalizedMessageId != null) {
      timestamp = entries.remove(
        _messageKey(normalizedPayload, normalizedMessageId),
      );
      if (timestamp != null) {
        entries.remove(_payloadKey(normalizedPayload));
      }
    }
    timestamp ??= entries.remove(_payloadKey(normalizedPayload));
    await _writeEntries(entries);
    return timestamp != null;
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
        // A corrupt-but-valid-JSON file (e.g. an array) is still a decode
        // failure — surface it rather than silently treating it as empty.
        _onLoadError(
          const FormatException(
            'recent-remote notification gate payload is not a JSON object',
          ),
          StackTrace.current,
        );
        return <String, int>{};
      }

      final entries = <String, int>{};
      for (final entry in decoded.entries) {
        final normalizedKey = _normalizeStoredKey(entry.key);
        final timestamp = _coerceTimestamp(entry.value);
        if (normalizedKey == null || timestamp == null) {
          continue;
        }
        final cutoff =
            _now().millisecondsSinceEpoch -
            _ttlForKey(normalizedKey).inMilliseconds;
        if (timestamp < cutoff) {
          continue;
        }
        entries[normalizedKey] = timestamp;
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

  static String? _normalizePayload(String? payload) {
    final normalized = payload?.trim();
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

  Duration _ttlForKey(String key) {
    return key.startsWith(_messagePrefix) ? messageTtl : ttl;
  }

  static String _payloadKey(String payload) => '$_payloadPrefix$payload';

  static String _messageKey(String payload, String messageId) =>
      '$_messagePrefix$payload|$messageId';

  static String? _normalizeStoredKey(String? key) {
    final normalizedKey = _normalizePayload(key);
    if (normalizedKey == null) {
      return null;
    }
    if (normalizedKey.startsWith(_payloadPrefix) ||
        normalizedKey.startsWith(_messagePrefix)) {
      return normalizedKey;
    }
    return _payloadKey(normalizedKey);
  }
}

const _payloadPrefix = 'payload:';
const _messagePrefix = 'message:';
