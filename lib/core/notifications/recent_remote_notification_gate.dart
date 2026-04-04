import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

const Duration recentRemoteNotificationTtl = Duration(seconds: 30);
const Duration recentRemoteNotificationMessageTtl = Duration(hours: 12);

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

class RecentRemoteNotificationGate {
  final String filePath;
  final Duration ttl;
  final Duration messageTtl;
  final DateTime Function() _now;

  RecentRemoteNotificationGate({
    String? filePath,
    Duration? ttl,
    Duration? messageTtl,
    DateTime Function()? now,
  }) : filePath =
           filePath ??
           '${Directory.systemTemp.path}/mknoon_recent_remote_notifications.json',
       ttl = ttl ?? recentRemoteNotificationTtl,
       messageTtl = messageTtl ?? recentRemoteNotificationMessageTtl,
       _now = now ?? DateTime.now;

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
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  Future<Map<String, int>> _loadEntries() async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return <String, int>{};
      }

      final raw = await file.readAsString();
      if (raw.trim().isEmpty) {
        return <String, int>{};
      }

      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
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
    } catch (_) {
      return <String, int>{};
    }
  }

  Future<void> _writeEntries(Map<String, int> entries) async {
    try {
      final file = File(filePath);
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
