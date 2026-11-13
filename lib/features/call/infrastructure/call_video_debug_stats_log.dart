import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;

/// Debug-only `[STATS]` lines for video device proofs. Not used in release.
final class CallVideoDebugStatsLog {
  List<String> lines(Iterable<webrtc.StatsReport> reports) => const [];
}
