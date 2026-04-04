import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

const Duration recentBackgroundNotificationTtl = Duration(hours: 12);

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

class RecentBackgroundNotificationGate {
  final String filePath;
  final Duration ttl;
  final DateTime Function() _now;

  RecentBackgroundNotificationGate({
    String? filePath,
    Duration? ttl,
    DateTime Function()? now,
  }) : filePath =
           filePath ??
           '${Directory.systemTemp.path}/mknoon_recent_background_notifications.json',
       ttl = ttl ?? recentBackgroundNotificationTtl,
       _now = now ?? DateTime.now;

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
        final key = _normalizeKey(entry.key);
        final timestamp = _coerceTimestamp(entry.value);
        if (key == null || timestamp == null || timestamp < cutoff) {
          continue;
        }
        entries[key] = timestamp;
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
