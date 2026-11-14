import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;

/// Debug-only `[STATS]` lines for video device proofs. Not used in release.
/// Timestamps are microseconds (pinned SDK), so kbps = bytes * 8000 / dt.
final class CallVideoDebugStatsLog {
  Map<String, (double, int)> _last = {};

  List<String> lines(Iterable<webrtc.StatsReport> reports) {
    final out = <String>[];
    final next = <String, (double, int)>{};
    for (final r in reports) {
      final v = r.values;
      final key = switch (r.type) {
        'outbound-rtp' => 'bytesSent',
        'inbound-rtp' => 'bytesReceived',
        _ => null,
      };
      if (key == null || (v['kind'] ?? v['mediaType']) != 'video') continue;
      final raw = v[key];
      final bytes = raw is num && raw >= 0 && raw == raw.truncateToDouble()
          ? raw.toInt()
          : null;
      var kbps = '-';
      if (bytes != null) {
        final previous = _last[r.id];
        if (previous != null &&
            r.timestamp > previous.$1 &&
            bytes >= previous.$2) {
          kbps = ((bytes - previous.$2) * 8000 / (r.timestamp - previous.$1))
              .round()
              .toString();
        }
        next[r.id] = (r.timestamp, bytes);
      }
      String f(String name) => '$name=${v[name] ?? '-'}';
      out.add(
        '[STATS] ${r.type} ts=${r.timestamp.round()} id=${r.id} ${f('rid')} '
        '$key=${bytes ?? '-'} kbps=$kbps ${f('frameWidth')} '
        '${f('frameHeight')} ${f('framesPerSecond')} '
        '${f('qualityLimitationReason')}',
      );
    }
    _last = next;
    return out;
  }
}
