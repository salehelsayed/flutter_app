import 'package:flutter_app/features/call/domain/call_engine.dart';
import 'package:flutter_app/features/call/infrastructure/call_stats_sampler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sampler = CallStatsSampler();

  test('empty sample cannot prove transport or media readiness', () {
    final sample = sampler.sample(const <CallStatsRecord>[]);

    expect(sample.selectedPairSucceeded, isFalse);
    expect(sample.selectedPairNominated, isFalse);
    expect(sample.dtlsReady, isFalse);
    expect(sample.transport, CallTransportClass.unknown);
    expect(sample.selectedRelayProtocol, CallRelayProtocol.unknown);
    expect(sample.inboundAudioRtpObserved, isFalse);
    expect(sample.outboundAudioRtpObserved, isFalse);
  });

  test(
    'collapses bidirectional audio RTP observations to booleans without retaining raw stats',
    () {
      final sample = sampler.sample(const <CallStatsRecord>[
        CallStatsRecord(
          id: 'private-inbound-report-id',
          type: 'inbound-rtp',
          values: <Object?, Object?>{
            'kind': 'audio',
            'packetsReceived': 7,
            'bytesReceived': 701,
            'ssrc': 123456,
            'trackIdentifier': 'private-track-id',
            'remoteId': 'private-remote-id',
            'audioLevel': 0.5,
            'totalAudioEnergy': 42.0,
            'address': '192.0.2.1',
            'sdp': 'private-sdp',
          },
        ),
        CallStatsRecord(
          id: 'private-outbound-report-id',
          type: 'outbound-rtp',
          values: <Object?, Object?>{
            'mediaType': 'AuDiO',
            'packetsSent': 9,
            'bytesSent': 902,
            'ssrc': 654321,
            'trackId': 'private-track-id',
            'remoteId': 'private-remote-id',
            'address': '198.51.100.2',
            'candidate': 'private-candidate',
          },
        ),
        CallStatsRecord(
          id: 'video-inbound',
          type: 'inbound-rtp',
          values: <Object?, Object?>{
            'kind': 'video',
            'packetsReceived': 99,
            'bytesReceived': 9999,
          },
        ),
        CallStatsRecord(
          id: 'video-outbound',
          type: 'outbound-rtp',
          values: <Object?, Object?>{
            'kind': 'video',
            'packetsSent': 99,
            'bytesSent': 9999,
          },
        ),
      ]);

      expect(sample.inboundAudioRtpObserved, isTrue);
      expect(sample.outboundAudioRtpObserved, isTrue);
      expect(
        sample.toString(),
        isNot(
          anyOf(
            contains('private-'),
            contains('192.0.2.1'),
            contains('198.51.100.2'),
            contains('123456'),
            contains('654321'),
            contains('701'),
            contains('902'),
          ),
        ),
      );
    },
  );

  test('ignores video missing-kind zero and incomplete audio RTP reports', () {
    const rejectedReports = <CallStatsRecord>[
      CallStatsRecord(
        id: 'video-inbound',
        type: 'inbound-rtp',
        values: <Object?, Object?>{
          'kind': 'video',
          'packetsReceived': 1,
          'bytesReceived': 1,
        },
      ),
      CallStatsRecord(
        id: 'missing-kind-outbound',
        type: 'outbound-rtp',
        values: <Object?, Object?>{'packetsSent': 1, 'bytesSent': 1},
      ),
      CallStatsRecord(
        id: 'zero-packets-inbound',
        type: 'inbound-rtp',
        values: <Object?, Object?>{
          'kind': 'audio',
          'packetsReceived': 0,
          'bytesReceived': 1,
        },
      ),
      CallStatsRecord(
        id: 'zero-bytes-outbound',
        type: 'outbound-rtp',
        values: <Object?, Object?>{
          'kind': 'audio',
          'packetsSent': 1,
          'bytesSent': 0,
        },
      ),
      CallStatsRecord(
        id: 'incomplete-inbound',
        type: 'inbound-rtp',
        values: <Object?, Object?>{'kind': 'audio', 'packetsReceived': 1},
      ),
      CallStatsRecord(
        id: 'string-counters-outbound',
        type: 'outbound-rtp',
        values: <Object?, Object?>{
          'kind': 'audio',
          'packetsSent': '1',
          'bytesSent': '1',
        },
      ),
    ];

    for (final report in rejectedReports) {
      final sample = sampler.sample(<CallStatsRecord>[report]);
      expect(sample.inboundAudioRtpObserved, isFalse, reason: report.id);
      expect(sample.outboundAudioRtpObserved, isFalse, reason: report.id);
    }
  });

  List<CallStatsRecord> selectedPair({
    required String? candidateType,
    required String protocol,
    String? relayProtocol,
    String pairState = 'succeeded',
    bool nominated = true,
    String dtlsState = 'connected',
    bool selectedByTransport = true,
    bool includeLocalCandidate = true,
  }) => <CallStatsRecord>[
    CallStatsRecord(
      id: 'transport',
      type: 'transport',
      values: <Object?, Object?>{
        if (selectedByTransport) 'selectedCandidatePairId': 'pair',
        'dtlsState': dtlsState,
      },
    ),
    CallStatsRecord(
      id: 'pair',
      type: 'candidate-pair',
      values: <Object?, Object?>{
        'state': pairState,
        'nominated': nominated,
        'localCandidateId': 'local',
      },
    ),
    if (includeLocalCandidate)
      CallStatsRecord(
        id: 'local',
        type: 'local-candidate',
        values: <Object?, Object?>{
          'candidateType': ?candidateType,
          'protocol': protocol,
          'relayProtocol': ?relayProtocol,
        },
      ),
  ];

  test(
    'classifies a nominated succeeded direct pair without retaining addresses',
    () {
      final sample = sampler.sample(
        selectedPair(candidateType: 'host', protocol: 'udp'),
      );

      expect(sample.selectedPairSucceeded, isTrue);
      expect(sample.selectedPairNominated, isTrue);
      expect(sample.dtlsReady, isTrue);
      expect(sample.transport, CallTransportClass.direct);
      expect(sample.selectedRelayProtocol, CallRelayProtocol.notRelay);
      expect(sample.toString(), isNot(contains('address')));
    },
  );

  test('classifies exact UDP TCP and TLS only from relayProtocol', () {
    for (final entry in const <String, CallRelayProtocol>{
      'udp': CallRelayProtocol.udp,
      'tcp': CallRelayProtocol.tcp,
      'tls': CallRelayProtocol.tls,
    }.entries) {
      final sample = sampler.sample(
        selectedPair(
          candidateType: 'relay',
          protocol: 'udp',
          relayProtocol: entry.key,
        ),
      );

      expect(sample.selectedRelayProtocol, entry.value);
      expect(
        sample.transport,
        entry.key == 'udp'
            ? CallTransportClass.turnUdp
            : CallTransportClass.turnTcpTls,
      );
    }
  });

  test('relayProtocol takes precedence over protocol for both classifiers', () {
    final sample = sampler.sample(
      selectedPair(
        candidateType: 'relay',
        protocol: 'udp',
        relayProtocol: 'tcp',
      ),
    );

    expect(sample.transport, CallTransportClass.turnTcpTls);
    expect(sample.selectedRelayProtocol, CallRelayProtocol.tcp);
  });

  test(
    'protocol preserves coarse fallback but cannot prove exact protocol',
    () {
      for (final entry in const <String, CallTransportClass>{
        'udp': CallTransportClass.turnUdp,
        'tcp': CallTransportClass.turnTcpTls,
        'tls': CallTransportClass.turnTcpTls,
      }.entries) {
        final sample = sampler.sample(
          selectedPair(candidateType: 'relay', protocol: entry.key),
        );

        expect(sample.transport, entry.value);
        expect(sample.selectedRelayProtocol, CallRelayProtocol.unknown);
      }
    },
  );

  test(
    'unrecognized relayProtocol stays exact unknown and keeps coarse rules',
    () {
      final sample = sampler.sample(
        selectedPair(
          candidateType: 'relay',
          protocol: 'udp',
          relayProtocol: 'quic',
        ),
      );

      expect(sample.transport, CallTransportClass.relay);
      expect(sample.selectedRelayProtocol, CallRelayProtocol.unknown);
    },
  );

  test('keeps missing blank and unrecognized candidate types unknown', () {
    for (final candidateType in <String?>[null, '', 'mystery']) {
      expect(
        sampler
            .sample(selectedPair(candidateType: candidateType, protocol: 'udp'))
            .transport,
        CallTransportClass.unknown,
        reason: 'candidateType=$candidateType',
      );
      expect(
        sampler
            .sample(selectedPair(candidateType: candidateType, protocol: 'udp'))
            .selectedRelayProtocol,
        CallRelayProtocol.unknown,
        reason: 'candidateType=$candidateType',
      );
    }
  });

  test('classifies only recognized non-relay candidate types as direct', () {
    for (final candidateType in const <String>['host', 'srflx', 'prflx']) {
      final sample = sampler.sample(
        selectedPair(candidateType: candidateType, protocol: 'udp'),
      );
      expect(
        sample.transport,
        CallTransportClass.direct,
        reason: 'candidateType=$candidateType',
      );
      expect(sample.selectedRelayProtocol, CallRelayProtocol.notRelay);
    }
  });

  test('supports selected-via-transport and nominated fallback shapes', () {
    final selected = sampler.sample(
      selectedPair(
        candidateType: 'relay',
        protocol: 'udp',
        relayProtocol: 'udp',
        nominated: false,
      ),
    );
    final nominated = sampler.sample(
      selectedPair(
        candidateType: 'relay',
        protocol: 'tcp',
        relayProtocol: 'tcp',
        selectedByTransport: false,
      ),
    );

    expect(selected.selectedPairNominated, isTrue);
    expect(selected.selectedRelayProtocol, CallRelayProtocol.udp);
    expect(nominated.selectedPairNominated, isTrue);
    expect(nominated.selectedRelayProtocol, CallRelayProtocol.tcp);
  });

  test('missing selected or local-candidate references remain unknown', () {
    final noSelectedPair = sampler.sample(const <CallStatsRecord>[
      CallStatsRecord(
        id: 'transport',
        type: 'transport',
        values: <Object?, Object?>{
          'selectedCandidatePairId': 'missing-pair',
          'dtlsState': 'connected',
        },
      ),
    ]);
    final noLocalCandidate = sampler.sample(
      selectedPair(
        candidateType: 'relay',
        protocol: 'udp',
        relayProtocol: 'udp',
        includeLocalCandidate: false,
      ),
    );

    expect(noSelectedPair.transport, CallTransportClass.unknown);
    expect(noSelectedPair.selectedRelayProtocol, CallRelayProtocol.unknown);
    expect(noLocalCandidate.transport, CallTransportClass.unknown);
    expect(noLocalCandidate.selectedRelayProtocol, CallRelayProtocol.unknown);
  });

  test('never upgrades incomplete transport state to ready', () {
    final sample = sampler.sample(
      selectedPair(
        candidateType: 'relay',
        protocol: 'udp',
        pairState: 'in-progress',
        nominated: false,
        dtlsState: 'connecting',
      ),
    );

    expect(sample.selectedPairSucceeded, isFalse);
    expect(sample.selectedPairNominated, isTrue);
    expect(sample.dtlsReady, isFalse);
  });
}
