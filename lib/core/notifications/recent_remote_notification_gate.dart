import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

const Duration recentRemoteNotificationTtl = Duration(seconds: 30);

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
  final DateTime Function() _now;

  RecentRemoteNotificationGate({
    String? filePath,
    Duration? ttl,
    DateTime Function()? now,
  }) : filePath =
           filePath ??
           '${Directory.systemTemp.path}/mknoon_recent_remote_notifications.json',
       ttl = ttl ?? recentRemoteNotificationTtl,
       _now = now ?? DateTime.now;

  Future<void> markPayload(String payload) async {
    final normalizedPayload = _normalizePayload(payload);
    if (normalizedPayload == null) {
      return;
    }

    final entries = await _loadEntries();
    entries[normalizedPayload] = _now().millisecondsSinceEpoch;
    await _writeEntries(entries);
  }

  Future<bool> consumeIfRecentPayload(String payload) async {
    final normalizedPayload = _normalizePayload(payload);
    if (normalizedPayload == null) {
      return false;
    }

    final entries = await _loadEntries();
    final timestamp = entries.remove(normalizedPayload);
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

      final cutoff = _now().millisecondsSinceEpoch - ttl.inMilliseconds;
      final entries = <String, int>{};
      for (final entry in decoded.entries) {
        final payload = _normalizePayload(entry.key);
        final timestamp = _coerceTimestamp(entry.value);
        if (payload == null || timestamp == null || timestamp < cutoff) {
          continue;
        }
        entries[payload] = timestamp;
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
}
