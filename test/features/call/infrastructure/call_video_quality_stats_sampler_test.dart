import 'package:flutter_app/features/call/domain/call_video_quality_policy.dart';
import 'package:flutter_app/features/call/infrastructure/call_video_quality_stats_sampler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;

List<rtc.StatsReport> reports(
  int second, {
  Object? available = 3000000,
  int? audioBytes,
  String reason = 'none',
  String track = 'camera',
  bool video = true,
  bool selected = true,
}) {
  final timestamp = second * 1000000.0;
  rtc.StatsReport report(String id, String type, Map<String, Object?> values) =>
      rtc.StatsReport(id, type, timestamp, values);
  return [
    report('transport', 'transport', {
      if (selected) 'selectedCandidatePairId': 'selected',
    }),
    report('selected', 'candidate-pair', {
      'state': 'succeeded',
      'nominated': true,
      'availableOutgoingBitrate': available,
    }),
    report('unselected', 'candidate-pair', {
      'state': 'succeeded',
      'availableOutgoingBitrate': 9000000,
    }),
    report('audio', 'outbound-rtp', {
      'kind': 'audio',
      'bytesSent': audioBytes ?? second * 8000,
    }),
    if (video) ...[
      report('source', 'media-source', {
        'kind': 'video',
        'trackIdentifier': track,
      }),
      report('video', 'outbound-rtp', {
        'kind': 'video',
        'mediaSourceId': 'source',
        'qualityLimitationReason': reason,
      }),
    ],
  ];
}

CallVideoQualityFeedback sample(
  CallVideoQualityStatsSampler sampler,
  List<rtc.StatsReport> values, {
  bool sending = true,
}) => sampler.sample(values, videoSending: sending, videoTrackId: 'camera');

void main() {
  test(
    'U3j-Q stats uses selected capacity and native microsecond audio deltas',
    () {
      final sampler = CallVideoQualityStatsSampler();
      final first = sample(sampler, reports(1));
      expect(first.audioBitrateBps, isNull);
      final next = sample(sampler, reports(2));
      expect(next.availableOutgoingBitrateBps, 3000000);
      expect(next.audioBitrateBps, 64000);
      expect(next.limitation, CallVideoQualityLimitation.none);
    },
  );

  for (final reason in ['bandwidth', 'cpu']) {
    test('U3j-Q stats retains current sender $reason limitation', () {
      final sampler = CallVideoQualityStatsSampler();
      final result = sample(sampler, reports(1, reason: reason));
      expect(result.limitation.name, reason);
    });
  }

  test('U3j-Q stats ignores a retired camera sender', () {
    final sampler = CallVideoQualityStatsSampler();
    sample(sampler, reports(1));
    final result = sample(
      sampler,
      reports(2, track: 'retired', reason: 'none'),
    );
    expect(result.limitation, CallVideoQualityLimitation.unknown);
  });

  test('U3j-Q stats duplicate or older snapshots cannot renew headroom', () {
    final sampler = CallVideoQualityStatsSampler();
    sample(sampler, reports(2));
    expect(
      sample(sampler, reports(2)).limitation,
      CallVideoQualityLimitation.unknown,
    );
    expect(
      sample(sampler, reports(1)).limitation,
      CallVideoQualityLimitation.unknown,
    );
    final fresh = sample(sampler, reports(3));
    expect(fresh.audioBitrateBps, 64000);
    expect(fresh.limitation, CallVideoQualityLimitation.none);
  });

  test(
    'U3j-Q stats counter resets and sampling gaps do not claim audio capacity',
    () {
      final sampler = CallVideoQualityStatsSampler();
      sample(sampler, reports(1));
      expect(
        sample(sampler, reports(2, audioBytes: 1)).audioBitrateBps,
        isNull,
      );
      expect(sample(sampler, reports(10)).audioBitrateBps, isNull);
      expect(sample(sampler, reports(11)).audioBitrateBps, 64000);
    },
  );

  for (final value in [null, -1, double.nan, double.infinity, '3000000']) {
    test('U3j-Q stats invalid capacity $value remains unknown', () {
      final sampler = CallVideoQualityStatsSampler();
      sample(sampler, reports(1));
      expect(
        sample(
          sampler,
          reports(2, available: value),
        ).availableOutgoingBitrateBps,
        isNull,
      );
    });
  }

  test(
    'U3j-Q stats no selected transport does not borrow an unrelated pair',
    () {
      final sampler = CallVideoQualityStatsSampler();
      expect(
        sample(
          sampler,
          reports(1, selected: false),
        ).availableOutgoingBitrateBps,
        isNull,
      );
    },
  );

  test('U3j-Q stats conflicting selected pairs remain unknown', () {
    final sampler = CallVideoQualityStatsSampler();
    final values = reports(1)
      ..add(
        rtc.StatsReport('other-transport', 'transport', 1000000, {
          'selectedCandidatePairId': 'unselected',
        }),
      );
    expect(sample(sampler, values).availableOutgoingBitrateBps, isNull);
  });

  test(
    'U3j-Q stats requires camera feedback while sending but permits paused recovery',
    () {
      final sampler = CallVideoQualityStatsSampler();
      expect(
        sample(sampler, reports(1, video: false)).limitation,
        CallVideoQualityLimitation.unknown,
      );
      final paused = sample(sampler, reports(2, video: false), sending: false);
      expect(paused.limitation, CallVideoQualityLimitation.none);
      expect(paused.audioBitrateBps, 64000);
    },
  );

  test('U3j-Q stats reset discards the previous camera audio baseline', () {
    final sampler = CallVideoQualityStatsSampler();
    sample(sampler, reports(1));
    expect(sample(sampler, reports(2)).audioBitrateBps, 64000);
    sampler.reset();
    expect(sample(sampler, reports(3)).audioBitrateBps, isNull);
  });
}
