final class StickerUsageDay {
  StickerUsageDay(this.intervalEndMs, Map<String, int> counts)
    : counts = Map.unmodifiable(counts);

  final int intervalEndMs;
  final Map<String, int> counts;
}

final class StickerUsageTally {
  StickerUsageTally({
    required Iterable<String> stickerIds,
    required this.retentionMs,
  }) : _stickerIds = Set.unmodifiable(stickerIds);

  static const _maximumCount = 9007199254740991;
  // A week normally needs eight buckets; travel can change midnight boundaries.
  static const _maximumDays = 32;
  final Set<String> _stickerIds;
  final int retentionMs;
  final _days = <int, Map<String, int>>{};

  void record(String stickerId, DateTime now) {
    prune(now);
    final local = now.toLocal();
    final end =
        DateTime(
          local.year,
          local.month,
          local.day + 1,
        ).millisecondsSinceEpoch -
        1;
    if (!_days.containsKey(end) && _days.length >= _maximumDays) {
      _days.remove(_days.keys.reduce((a, b) => a < b ? a : b));
    }
    final id = _stickerIds.contains(stickerId) ? stickerId : 'unknown';
    final counts = _days.putIfAbsent(end, () => <String, int>{});
    final previous = counts[id] ?? 0;
    if (previous < _maximumCount) counts[id] = previous + 1;
  }

  void restore(Object? raw, DateTime now) {
    clear();
    if (raw is! List) return;
    final cutoff = now.millisecondsSinceEpoch - retentionMs;
    final latest = now.add(const Duration(days: 2)).millisecondsSinceEpoch;
    for (final item in raw.take(_maximumDays)) {
      if (item is! Map) continue;
      final end = item['intervalEndMs'];
      final rawCounts = item['counts'];
      if (end is! int ||
          end < cutoff ||
          end > latest ||
          end % 60000 != 59999 ||
          rawCounts is! Map ||
          _days.containsKey(end)) {
        continue;
      }
      final counts = <String, int>{};
      // Iterate the closed vocabulary, never arbitrary keys from disk.
      for (final id in _stickerIds) {
        final count = rawCounts[id];
        if (count is int && count > 0 && count <= _maximumCount) {
          counts[id] = count;
        }
      }
      if (counts.isNotEmpty) _days[end] = counts;
    }
  }

  bool prune(DateTime now) {
    final before = _days.length;
    final cutoff = now.millisecondsSinceEpoch - retentionMs;
    _days.removeWhere((end, _) => end < cutoff);
    return before != _days.length;
  }

  List<StickerUsageDay> completedDays(DateTime now) {
    prune(now);
    final ends =
        _days.keys.where((end) => end < now.millisecondsSinceEpoch).toList()
          ..sort();
    return [for (final end in ends) StickerUsageDay(end, _days[end]!)];
  }

  void remove(int intervalEndMs, String stickerId) {
    final counts = _days[intervalEndMs];
    if (counts == null) return;
    counts.remove(stickerId);
    if (counts.isEmpty) _days.remove(intervalEndMs);
  }

  void clear() => _days.clear();

  List<Map<String, Object?>> toJson() => [
    for (final entry in _days.entries)
      {'intervalEndMs': entry.key, 'counts': Map<String, int>.of(entry.value)},
  ];
}
