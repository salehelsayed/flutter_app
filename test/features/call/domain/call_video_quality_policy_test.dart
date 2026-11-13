import 'package:flutter_app/features/call/domain/call_video_quality_environment.dart';
import 'package:flutter_app/features/call/domain/call_video_quality_policy.dart';
import 'package:flutter_test/flutter_test.dart';

const wifi = CallVideoQualityEnvironment(
  networkClass: CallVideoNetworkClass.wifi,
  lowDataMode: false,
  metered: false,
  thermalState: CallVideoThermalState.nominal,
);
const headroom = CallVideoQualityFeedback(
  limitation: CallVideoQualityLimitation.none,
  availableOutgoingBitrateBps: 3000000,
  audioBitrateBps: 64000,
);
const limited = CallVideoQualityFeedback(
  limitation: CallVideoQualityLimitation.bandwidth,
  availableOutgoingBitrateBps: 200000,
  audioBitrateBps: 64000,
);

CallVideoQualityPolicy policy([
  CallVideoQualityEnvironment environment = wifi,
]) {
  final result = CallVideoQualityPolicy();
  result.setEnvironment(environment, now: Duration.zero);
  return result;
}

void reachHigh(CallVideoQualityPolicy p) {
  observeSeconds(p, headroom, 0, 30);
}

void observeSeconds(
  CallVideoQualityPolicy p,
  CallVideoQualityFeedback feedback,
  int from,
  int through,
) {
  for (var second = from; second <= through; second++) {
    p.observe(feedback, now: Duration(seconds: second));
  }
}

void main() {
  test('U3j-Q starts at the approved video ceiling without a minimum rate', () {
    final d = policy().decision;
    expect(d.paused, isFalse);
    expect(d.tier.width, 640);
    expect(d.tier.height, 360);
    expect(d.tier.framesPerSecond, 24);
    expect(d.tier.maxBitrateBps, 600000);
  });

  test(
    'U3j-Q measured headroom restores only one tier after fifteen seconds',
    () {
      final p = policy();
      observeSeconds(p, headroom, 0, 14);
      expect(p.decision.tier, CallVideoQualityTier.standard);
      p.observe(headroom, now: const Duration(seconds: 15));
      expect(p.decision.tier, CallVideoQualityTier.medium);
      observeSeconds(p, headroom, 16, 29);
      expect(p.decision.tier, CallVideoQualityTier.medium);
      p.observe(headroom, now: const Duration(seconds: 30));
      expect(p.decision.tier, CallVideoQualityTier.high);
      p.observe(headroom, now: const Duration(minutes: 2));
      expect(p.decision.tier, CallVideoQualityTier.high);
      expect(p.decision.tier.maxBitrateBps, 2000000);
    },
  );

  for (final metered in [false, true]) {
    test('U3j-Q cellular stays capped even when metered=$metered', () {
      final p = policy(
        CallVideoQualityEnvironment(
          networkClass: CallVideoNetworkClass.cellular,
          lowDataMode: false,
          metered: metered,
          thermalState: CallVideoThermalState.nominal,
        ),
      );
      reachHigh(p);
      expect(p.decision.tier, CallVideoQualityTier.medium);
      expect(p.decision.tier.maxBitrateBps, 1000000);
    });
  }

  test('U3j-Q metered wifi uses the cellular budget', () {
    final p = policy(
      const CallVideoQualityEnvironment(
        networkClass: CallVideoNetworkClass.wifi,
        lowDataMode: false,
        metered: true,
        thermalState: CallVideoThermalState.nominal,
      ),
    );
    reachHigh(p);
    expect(p.decision.tier, CallVideoQualityTier.medium);
  });

  test('U3j-Q Low Data clamps a running HD sender immediately', () {
    final p = policy();
    reachHigh(p);
    expect(p.decision.tier, CallVideoQualityTier.high);
    p.setEnvironment(
      const CallVideoQualityEnvironment(
        networkClass: CallVideoNetworkClass.wifi,
        lowDataMode: true,
        metered: false,
        thermalState: CallVideoThermalState.nominal,
      ),
      now: const Duration(seconds: 31),
    );
    expect(p.decision.tier, CallVideoQualityTier.standard);
    p.observe(headroom, now: const Duration(seconds: 90));
    expect(p.decision.tier, CallVideoQualityTier.standard);
  });

  test('U3j-Q unknown OS inputs cannot authorize a higher tier', () {
    final p = policy(CallVideoQualityEnvironment.unknown);
    reachHigh(p);
    expect(p.decision.tier, CallVideoQualityTier.standard);
  });

  for (final reason in [
    CallVideoQualityLimitation.bandwidth,
    CallVideoQualityLimitation.cpu,
  ]) {
    test('U3j-Q sustained $reason lowers capture after two seconds', () {
      final p = policy();
      reachHigh(p);
      final bad = CallVideoQualityFeedback(limitation: reason);
      p.observe(bad, now: const Duration(seconds: 31));
      p.observe(bad, now: const Duration(seconds: 32));
      expect(p.decision.tier, CallVideoQualityTier.high);
      p.observe(bad, now: const Duration(seconds: 33));
      expect(p.decision.tier, CallVideoQualityTier.medium);
      p.observe(bad, now: const Duration(seconds: 35));
      expect(p.decision.tier, CallVideoQualityTier.standard);
      p.observe(bad, now: const Duration(seconds: 37));
      expect(p.decision.tier, CallVideoQualityTier.low);
      expect(p.decision.tier.framesPerSecond, 15);
      expect(p.decision.tier.maxBitrateBps, 250000);
      p.observe(bad, now: const Duration(seconds: 39));
      expect(p.decision.paused, isTrue);
      expect(
        p.decision.pauseReason,
        CallVideoQualityPauseReason.sustainedLimitation,
      );
    });
  }

  test('U3j-Q a brief limitation does not lower the current tier', () {
    final p = policy();
    reachHigh(p);
    p.observe(limited, now: const Duration(seconds: 31));
    p.observe(headroom, now: const Duration(milliseconds: 32999));
    expect(p.decision.tier, CallVideoQualityTier.high);
  });

  test('U3j-Q missing feedback interrupts the headroom window', () {
    final p = policy();
    p.observe(headroom, now: Duration.zero);
    p.observe(
      CallVideoQualityFeedback.unknown,
      now: const Duration(seconds: 14),
    );
    p.observe(headroom, now: const Duration(seconds: 15));
    expect(p.decision.tier, CallVideoQualityTier.standard);
    observeSeconds(p, headroom, 16, 29);
    expect(p.decision.tier, CallVideoQualityTier.standard);
    p.observe(headroom, now: const Duration(seconds: 30));
    expect(p.decision.tier, CallVideoQualityTier.medium);
  });

  test('U3j-Q measured outgoing capacity must also leave room for audio', () {
    final p = policy();
    const onlyVideo = CallVideoQualityFeedback(
      limitation: CallVideoQualityLimitation.none,
      availableOutgoingBitrateBps: 1000000,
      audioBitrateBps: 64000,
    );
    p.observe(onlyVideo, now: Duration.zero);
    p.observe(onlyVideo, now: const Duration(seconds: 30));
    expect(p.decision.tier, CallVideoQualityTier.standard);
    observeSeconds(p, headroom, 31, 46);
    expect(p.decision.tier, CallVideoQualityTier.medium);
  });

  test('U3j-Q serious heat immediately lowers capture to the low tier', () {
    final p = policy();
    reachHigh(p);
    p.setEnvironment(
      const CallVideoQualityEnvironment(
        networkClass: CallVideoNetworkClass.wifi,
        lowDataMode: false,
        metered: false,
        thermalState: CallVideoThermalState.serious,
      ),
      now: const Duration(seconds: 31),
    );
    expect(p.decision.tier, CallVideoQualityTier.low);
    expect(p.decision.paused, isFalse);
    p.observe(headroom, now: const Duration(seconds: 70));
    expect(p.decision.tier, CallVideoQualityTier.low);
  });

  test('U3j-Q critical heat pauses and unknown state cannot clear it', () {
    final p = policy();
    p.setEnvironment(
      const CallVideoQualityEnvironment(
        thermalState: CallVideoThermalState.critical,
      ),
      now: Duration.zero,
    );
    expect(p.decision.paused, isTrue);
    expect(p.decision.pauseReason, CallVideoQualityPauseReason.thermal);
    p.setEnvironment(
      CallVideoQualityEnvironment.unknown,
      now: const Duration(seconds: 1),
    );
    p.observe(headroom, now: const Duration(seconds: 60));
    expect(p.decision.paused, isTrue);
    p.resetForNewCameraIntent(now: const Duration(seconds: 61));
    expect(p.decision.paused, isTrue);
  });

  test(
    'U3j-Q cooling resumes at the low tier after stable measured headroom',
    () {
      final p = policy();
      p.setEnvironment(
        const CallVideoQualityEnvironment(
          thermalState: CallVideoThermalState.critical,
        ),
        now: Duration.zero,
      );
      p.setEnvironment(wifi, now: const Duration(seconds: 1));
      observeSeconds(p, headroom, 1, 15);
      expect(p.decision.paused, isTrue);
      p.observe(headroom, now: const Duration(seconds: 16));
      expect(p.decision.paused, isFalse);
      expect(p.decision.tier, CallVideoQualityTier.low);
      observeSeconds(p, headroom, 17, 31);
      expect(p.decision.tier, CallVideoQualityTier.standard);
    },
  );

  test(
    'U3j-Q older observations cannot renew or bypass a pending downshift',
    () {
      final p = policy();
      reachHigh(p);
      p.observe(limited, now: const Duration(seconds: 31));
      p.observe(headroom, now: const Duration(seconds: 1));
      p.observe(limited, now: const Duration(seconds: 33));
      expect(p.decision.tier, CallVideoQualityTier.medium);
    },
  );

  test('U3j-Q relaxing a cap needs a new recovery window', () {
    final p = policy(
      const CallVideoQualityEnvironment(
        networkClass: CallVideoNetworkClass.wifi,
        lowDataMode: true,
        metered: false,
        thermalState: CallVideoThermalState.nominal,
      ),
    );
    p.observe(headroom, now: Duration.zero);
    p.observe(headroom, now: const Duration(seconds: 60));
    p.setEnvironment(wifi, now: const Duration(seconds: 61));
    observeSeconds(p, headroom, 61, 75);
    expect(p.decision.tier, CallVideoQualityTier.standard);
    p.observe(headroom, now: const Duration(seconds: 76));
    expect(p.decision.tier, CallVideoQualityTier.medium);
  });

  test('U3j-Q unobserved time cannot count as sustained headroom', () {
    final p = policy();
    p.observe(headroom, now: Duration.zero);
    p.observe(headroom, now: const Duration(seconds: 60));
    expect(p.decision.tier, CallVideoQualityTier.standard);
    observeSeconds(p, headroom, 61, 74);
    expect(p.decision.tier, CallVideoQualityTier.standard);
    p.observe(headroom, now: const Duration(seconds: 75));
    expect(p.decision.tier, CallVideoQualityTier.medium);
  });

  test(
    'U3j-Q a repeated unchanged environment does not restart healthy timing',
    () {
      final p = policy();
      observeSeconds(p, headroom, 0, 10);
      p.setEnvironment(wifi, now: const Duration(seconds: 10));
      observeSeconds(p, headroom, 11, 15);
      expect(p.decision.tier, CallVideoQualityTier.medium);
    },
  );
}
