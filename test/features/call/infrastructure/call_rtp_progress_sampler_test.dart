import 'package:flutter_app/features/call/infrastructure/call_stats_sampler.dart';
import 'package:flutter_test/flutter_test.dart';

List<CallStatsRecord> sample(int received, int sent, {String kind = 'audio'}) =>
    [
      CallStatsRecord(
        id: 'private-inbound-id',
        type: 'inbound-rtp',
        values: {
          'kind': kind,
          'packetsReceived': received,
          'bytesReceived': received * 40,
          'address': 'private-address',
        },
      ),
      CallStatsRecord(
        id: 'private-outbound-id',
        type: 'outbound-rtp',
        values: {'kind': kind, 'packetsSent': sent, 'bytesSent': sent * 40},
      ),
    ];

void main() {
  test(
    'unchanged previously nonzero RTP cannot prove continuing media flow',
    () {
      final sampler = CallRtpProgressSampler();
      final first = sampler.sample(sample(10, 10));
      final unchanged = sampler.sample(sample(10, 10));
      expect(first.inbound || first.outbound, isFalse);
      expect(unchanged.inbound || unchanged.outbound, isFalse);
      final oneWay = sampler.sample(sample(11, 10));
      expect(oneWay.inbound, isTrue);
      expect(oneWay.outbound, isFalse);
      final both = sampler.sample(sample(12, 11));
      expect(both.inbound && both.outbound, isTrue);
      expect(both.toString(), isNot(contains('private')));
    },
  );

  test('reset, missing and video counters cannot invent audio progress', () {
    final sampler = CallRtpProgressSampler();
    sampler.sample(sample(100, 100));
    final reset = sampler.sample(sample(1, 1));
    expect(reset.inbound || reset.outbound, isFalse);
    sampler.sample(const []);
    final afterGap = sampler.sample(sample(10, 10));
    expect(afterGap.inbound || afterGap.outbound, isFalse);
    final video = sampler.sample(sample(100, 100, kind: 'video'));
    expect(video.inbound || video.outbound, isFalse);
  });
}
