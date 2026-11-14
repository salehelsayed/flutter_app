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
  CallVideoQualityEnvironment _environment =
      CallVideoQualityEnvironment.unknown;
  CallVideoQualityTier _tier = CallVideoQualityTier.standard;
  CallVideoQualityPauseReason _pause = CallVideoQualityPauseReason.none;
  bool _criticalHeat = false;
  Duration _lastNow = Duration.zero;
  Duration? _lastFeedback, _limitedSince, _headroomSince;

  // Initial product tuning, not measured encoder/device acceptance thresholds.
  static const _lowerAfter = Duration(seconds: 2);
  static const _raiseAfter = Duration(seconds: 15);
  static const _maximumFeedbackGap = Duration(seconds: 2);

  CallVideoQualityDecision get decision =>
      CallVideoQualityDecision(tier: _tier, pauseReason: _pause);

  CallVideoQualityTier get _cap {
    if (_environment.thermalState == CallVideoThermalState.serious ||
        _criticalHeat) {
      return CallVideoQualityTier.low;
    }
    if (_environment.lowDataMode != false ||
        _environment.metered == null ||
        _environment.thermalState == CallVideoThermalState.unknown) {
      return CallVideoQualityTier.standard;
    }
    return switch (_environment.networkClass) {
      CallVideoNetworkClass.cellular => CallVideoQualityTier.medium,
      CallVideoNetworkClass.wifi =>
        _environment.metered!
            ? CallVideoQualityTier.medium
            : CallVideoQualityTier.high,
      CallVideoNetworkClass.unknown ||
      CallVideoNetworkClass.other => CallVideoQualityTier.standard,
    };
  }

  void setEnvironment(
    CallVideoQualityEnvironment environment, {
    required Duration now,
  }) {
    if (now < _lastNow) return;
    _lastNow = now;
    final previous = _environment;
    if (previous.networkClass == environment.networkClass &&
        previous.lowDataMode == environment.lowDataMode &&
        previous.metered == environment.metered &&
        previous.thermalState == environment.thermalState) {
      return;
    }
    _environment = environment;
    if (environment.thermalState == CallVideoThermalState.critical) {
      _criticalHeat = true;
      _pause = CallVideoQualityPauseReason.thermal;
    } else if (environment.thermalState != CallVideoThermalState.unknown) {
      _criticalHeat = false;
    }
    if (_tier.index > _cap.index) _tier = _cap;
    _limitedSince = null;
    _headroomSince = null;
  }

  void observe(CallVideoQualityFeedback feedback, {required Duration now}) {
    if (now < _lastNow || (_lastFeedback != null && now <= _lastFeedback!)) {
      return;
    }
    _lastNow = now;
    if (_lastFeedback != null && now - _lastFeedback! > _maximumFeedbackGap) {
      _limitedSince = null;
      _headroomSince = null;
    }
    _lastFeedback = now;
    if (_criticalHeat ||
        (_pause == CallVideoQualityPauseReason.thermal &&
            _environment.thermalState == CallVideoThermalState.unknown)) {
      _limitedSince = null;
      _headroomSince = null;
      return;
    }
    if (feedback.limitation == CallVideoQualityLimitation.bandwidth ||
        feedback.limitation == CallVideoQualityLimitation.cpu) {
      _headroomSince = null;
      _limitedSince ??= now;
      if (now - _limitedSince! >= _lowerAfter) {
        if (_tier == CallVideoQualityTier.low) {
          if (_pause == CallVideoQualityPauseReason.none) {
            _pause = CallVideoQualityPauseReason.sustainedLimitation;
          }
        } else {
          _tier = CallVideoQualityTier.values[_tier.index - 1];
        }
        _limitedSince = now;
      }
      return;
    }
    _limitedSince = null;
    if (feedback.limitation != CallVideoQualityLimitation.none) {
      _headroomSince = null;
      return;
    }
    final paused = _pause != CallVideoQualityPauseReason.none;
    if (!paused && _tier.index >= _cap.index) {
      _headroomSince = null;
      return;
    }
    final next = paused
        ? CallVideoQualityTier.low
        : CallVideoQualityTier.values[_tier.index + 1];
    final available = feedback.availableOutgoingBitrateBps;
    final audio = feedback.audioBitrateBps;
    if (available == null ||
        audio == null ||
        audio < 0 ||
        available < next.maxBitrateBps + audio) {
      _headroomSince = null;
      return;
    }
    _headroomSince ??= now;
    if (now - _headroomSince! >= _raiseAfter) {
      _tier = next;
      _pause = CallVideoQualityPauseReason.none;
      _headroomSince = now;
    }
  }

  void resetForNewCameraIntent({required Duration now}) {
    if (now < _lastNow) return;
    _lastNow = now;
    _lastFeedback = null;
    _limitedSince = null;
    _headroomSince = null;
    if (_criticalHeat ||
        (_pause == CallVideoQualityPauseReason.thermal &&
            _environment.thermalState == CallVideoThermalState.unknown)) {
      _tier = CallVideoQualityTier.low;
      _pause = CallVideoQualityPauseReason.thermal;
      return;
    }
    _tier = _pause == CallVideoQualityPauseReason.thermal
        ? CallVideoQualityTier.low
        : CallVideoQualityTier.standard;
    if (_tier.index > _cap.index) _tier = _cap;
    _pause = CallVideoQualityPauseReason.none;
  }
}
