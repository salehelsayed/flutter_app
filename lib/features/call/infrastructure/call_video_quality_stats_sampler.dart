import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;

import '../domain/call_video_quality_policy.dart';

/// Normalizes the pinned native SDK's microsecond timestamps and current
/// sender/transport feedback. No transport identifiers leave this boundary.
final class CallVideoQualityStatsSampler {
  // Compile-only RED seam; behavior follows the frozen causal tests.
  CallVideoQualityFeedback sample(
    Iterable<webrtc.StatsReport> reports, {
    required bool videoSending,
    String? videoTrackId,
  }) => CallVideoQualityFeedback.unknown;

  void reset() {}
}
