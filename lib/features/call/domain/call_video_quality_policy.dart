import 'call_video_quality_environment.dart';

/// Per-sender video ceilings. Audio and transport overhead are separate.
enum CallVideoQualityTier {
  low(width: 320, height: 180, framesPerSecond: 15, maxBitrateBps: 250000),
  standard(width: 640, height: 360, framesPerSecond: 24, maxBitrateBps: 600000),
  medium(width: 960, height: 540, framesPerSecond: 24, maxBitrateBps: 1000000),
  high(width: 1280, height: 720, framesPerSecond: 30, maxBitrateBps: 2000000);

  const CallVideoQualityTier({
    required this.width,
    required this.height,
    required this.framesPerSecond,
    required this.maxBitrateBps,
  });

  final int width;
  final int height;
  final int framesPerSecond;
  final int maxBitrateBps;
}

enum CallVideoQualityLimitation { unknown, none, bandwidth, cpu }

/// Current, normalized native feedback without transport identifiers.
final class CallVideoQualityFeedback {
  const CallVideoQualityFeedback({
    this.limitation = CallVideoQualityLimitation.unknown,
    this.availableOutgoingBitrateBps,
    this.audioBitrateBps,
  });

  static const unknown = CallVideoQualityFeedback();

  final CallVideoQualityLimitation limitation;
  final int? availableOutgoingBitrateBps;
  final int? audioBitrateBps;
}

enum CallVideoQualityPauseReason { none, thermal, sustainedLimitation }

final class CallVideoQualityDecision {
  const CallVideoQualityDecision({
    required this.tier,
    this.pauseReason = CallVideoQualityPauseReason.none,
  });

  final CallVideoQualityTier tier;
  final CallVideoQualityPauseReason pauseReason;
  bool get paused => pauseReason != CallVideoQualityPauseReason.none;
}

/// Optional input on the existing session; it does not grant camera consent.
abstract interface class CallVideoQualityEnvironmentConsumer {
  void updateQualityEnvironment(CallVideoQualityEnvironment environment);
}

/// Applies approved ceilings and hysteresis using owner-monotonic elapsed time.
/// The session remains responsible for current consent and native effects.
final class CallVideoQualityPolicy {
  CallVideoQualityDecision get decision =>
      const CallVideoQualityDecision(tier: CallVideoQualityTier.standard);

  // Compile-only RED seams; behavior is implemented after the causal cases freeze.
  void setEnvironment(
    CallVideoQualityEnvironment environment, {
    required Duration now,
  }) {}

  void observe(CallVideoQualityFeedback feedback, {required Duration now}) {}

  void resetForNewCameraIntent({required Duration now}) {}
}
