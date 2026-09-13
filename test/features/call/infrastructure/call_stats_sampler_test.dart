import 'package:flutter_app/features/call/domain/call_engine.dart';
import 'package:flutter_app/features/call/infrastructure/call_stats_sampler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sampler = CallStatsSampler();

  List<CallStatsRecord> familyPair({
    Object? local = '192.0.2.10',
    Object? remote = '2001:db8::20',
    String localType = 'host',
    String remoteType = 'relay',
    String? relayProtocol,
    String pairId = 'pair',
    Map<Object?, Object?> localExtra = const {},
  }) => [
    CallStatsRecord(
      id: 'transport',
      type: 'transport',
      values: {'selectedCandidatePairId': pairId, 'dtlsState': 'connected'},
    ),
    CallStatsRecord(
      id: 'pair',
      type: 'candidate-pair',
      values: {
        'state': 'succeeded',
        'nominated': true,
        'localCandidateId': 'local',
        'remoteCandidateId': 'remote',
      },
    ),
    CallStatsRecord(
      id: 'local',
      type: 'local-candidate',
      values: {
        'address': local,
        'candidateType': localType,
        'protocol': 'udp',
        'relayProtocol': ?relayProtocol,
        ...localExtra,
      },
    ),
    CallStatsRecord(
      id: 'remote',
      type: 'remote-candidate',
      values: {
        'address': remote,
        'candidateType': remoteType,
        'protocol': 'udp',
      },
    ),
  ];

  test(
    'selected candidate families are separate from local and whole-pair routes',
    () {
      final sample = sampler.sample(familyPair());
      expect(sample.selectedLocalCandidateFamily, CallAddressFamily.ipv4);
      expect(sample.selectedRemoteCandidateFamily, CallAddressFamily.ipv6);
      expect(sample.transport, CallTransportClass.direct);
      expect(sample.selectedRelayProtocol, CallRelayProtocol.notRelay);
      expect(sample.pairRelayInvolvement, CallPairRelayInvolvement.remote);
      expect(sample.localTurnConnectionFamily, CallAddressFamily.unknown);
      expect(sample.remoteTurnConnectionFamily, CallAddressFamily.unknown);
    },
  );

  test(
    'TURN allocations and remapped local prflx never identify client-to-TURN families',
    () {
      for (final type in ['relay', 'prflx']) {
        final sample = sampler.sample(
          familyPair(
            local: '2001:db8::10',
            remote: '192.0.2.20',
            localType: type,
            relayProtocol: 'tcp',
            localExtra: {
              'url': 'turn:192.0.2.99:3478?transport=tcp',
              'relatedAddress': '192.0.2.88',
              'networkType': 'wifi',
              'usernameFragment': 'PRIVATE',
              'port': 6543,
            },
          ),
        );
        expect(sample.transport, CallTransportClass.turnTcpTls);
        expect(sample.pairRelayInvolvement, CallPairRelayInvolvement.both);
        expect(sample.selectedLocalCandidateFamily, CallAddressFamily.ipv6);
        expect(sample.selectedRemoteCandidateFamily, CallAddressFamily.ipv4);
        final values = sample.toLocalDiagnosticValues();
        expect(values['localTurnConnectionFamily'], 'unknown');
        expect(values['remoteTurnConnectionFamily'], 'unknown');
        expect(
          values.toString(),
          isNot(
            anyOf(
              contains('192.0.2'),
              contains('2001:db8'),
              contains('PRIVATE'),
              contains('6543'),
              contains('turn:'),
            ),
          ),
        );
      }
      expect(
        sampler.sample(familyPair(remoteType: 'prflx')).pairRelayInvolvement,
        CallPairRelayInvolvement.unknown,
      );
    },
  );

  test(
    'literal family parsing preserves missing malformed redacted and mapped ambiguity',
    () {
      for (final value in <Object?>[
        null,
        '',
        'redacted',
        'host.local',
        'turn.example.invalid',
        '0.0.0.0',
        '::',
        '::ffff:192.0.2.1',
        '::ffff:c000:201',
        '::192.0.2.1',
        '::c000:201',
        '[2001:db8::1]:3478',
        '[2001:db8::1]',
        '192.0.2.1:1234',
        'fe80::1%private-interface',
        '2001:db8:::1',
        '999.0.0.1',
        ' 192.0.2.1',
        42,
        true,
        <String>['192.0.2.1'],
      ]) {
        final sample = sampler.sample(familyPair(local: value, remote: value));
        expect(
          sample.selectedLocalCandidateFamily,
          CallAddressFamily.unknown,
          reason: '$value',
        );
        expect(
          sample.selectedRemoteCandidateFamily,
          CallAddressFamily.unknown,
          reason: '$value',
        );
      }
      for (final value in ['2001:db8::1', '2001:DB8:0:1::2', '::1']) {
        expect(
          sampler.sample(familyPair(local: value)).selectedLocalCandidateFamily,
          CallAddressFamily.ipv6,
        );
      }
      expect(
        sampler
            .sample(familyPair(local: null, localExtra: {'ip': '192.0.2.1'}))
            .selectedLocalCandidateFamily,
        CallAddressFamily.unknown,
      );
      expect(
        sampler
            .sample(familyPair(localExtra: {'ip': '2001:db8::1'}))
            .selectedLocalCandidateFamily,
        CallAddressFamily.unknown,
      );
      final legacy = familyPair();
      final values = Map<Object?, Object?>.of(legacy[2].values)
        ..remove('address');
      legacy[2] = CallStatsRecord(
        id: 'local',
        type: 'local-candidate',
        values: {...values, 'ip': '192.0.2.1'},
      );
      expect(
        sampler.sample(legacy).selectedLocalCandidateFamily,
        CallAddressFamily.ipv4,
      );
    },
  );

  test(
    'transport reference wins and unobserved candidate pairs cannot supply a family',
    () {
      final rows = familyPair();
      rows.insert(
        0,
        const CallStatsRecord(
          id: 'unused',
          type: 'candidate-pair',
          values: {
            'nominated': true,
            'selected': true,
            'localCandidateId': 'unused-local',
            'state': 'succeeded',
          },
        ),
      );
      rows.add(
        const CallStatsRecord(
          id: 'unused-local',
          type: 'local-candidate',
          values: {'address': '2001:db8::99', 'candidateType': 'relay'},
        ),
      );
      expect(
        sampler.sample(rows).selectedLocalCandidateFamily,
        CallAddressFamily.ipv4,
      );
      rows.removeWhere((r) => r.type == 'transport');
      expect(
        sampler.sample(rows).selectedLocalCandidateFamily,
        CallAddressFamily.ipv6,
      );
      final nominatedFirst = sampler.sample([...rows.skip(1), rows.first]);
      expect(
        nominatedFirst.transport,
        CallTransportClass.direct,
        reason: 'existing readiness/privacy contract is preserved',
      );
      expect(nominatedFirst.toLocalDiagnosticValues()['transport'], 'relay');
      expect(
        nominatedFirst.selectedLocalCandidateFamily,
        CallAddressFamily.ipv6,
        reason:
            'diagnostic local route and family follow the same selected pair',
      );
      rows[0] = const CallStatsRecord(
        id: 'unused',
        type: 'candidate-pair',
        values: {
          'nominated': true,
          'localCandidateId': 'unused-local',
          'state': 'succeeded',
        },
      );
      expect(
        sampler.sample(rows).selectedLocalCandidateFamily,
        CallAddressFamily.unknown,
      );
      expect(
        sampler
            .sample(familyPair(pairId: 'missing'))
            .selectedLocalCandidateFamily,
        CallAddressFamily.unknown,
      );
      final conflicting = familyPair()
        ..add(
          const CallStatsRecord(
            id: 'other-transport',
            type: 'transport',
            values: {'selectedCandidatePairId': 'another-pair'},
          ),
        );
      expect(
        sampler.sample(conflicting).selectedLocalCandidateFamily,
        CallAddressFamily.unknown,
      );
      final duplicate = familyPair()..add(familyPair(local: '2001:db8::99')[2]);
      expect(
        sampler.sample(duplicate).selectedLocalCandidateFamily,
        CallAddressFamily.unknown,
      );
    },
  );

  test(
    'pair replacement and ICE observation generations never reuse family evidence',
    () {
      final first = sampler.sample(familyPair(), iceGeneration: 0);
      final second = sampler.sample(
        familyPair(local: '2001:db8::11', remote: '192.0.2.12'),
        iceGeneration: 1,
      );
      expect(first.selectedLocalCandidateFamily, CallAddressFamily.ipv4);
      expect(second.selectedLocalCandidateFamily, CallAddressFamily.ipv6);
      expect(second.toLocalDiagnosticValues()['generation'], 1);
      final missing = sampler.sample(
        familyPair(pairId: 'previous-generation'),
        iceGeneration: 2,
      );
      expect(missing.selectedLocalCandidateFamily, CallAddressFamily.unknown);
      expect(missing.selectedPairState, CallSelectedPairState.unknown);
      expect(missing.observationIceGeneration, 2);
      expect(sampler.sample([], iceGeneration: 3).observationIceGeneration, 3);
    },
  );

  test('candidate references must point to the correct typed row', () {
    for (final index in [2, 3]) {
      final rows = familyPair();
      rows[index] = CallStatsRecord(
        id: rows[index].id,
        type: 'candidate-pair',
        values: rows[index].values,
      );
      final sample = sampler.sample(rows);
      expect(
        index == 2
            ? sample.selectedLocalCandidateFamily
            : sample.selectedRemoteCandidateFamily,
        CallAddressFamily.unknown,
      );
      expect(sample.pairRelayInvolvement, CallPairRelayInvolvement.unknown);
    }
  });

  test(
    'failed selected pair retains family evidence without becoming ready',
    () {
      final rows = familyPair();
      rows[1] = CallStatsRecord(
        id: 'pair',
        type: 'candidate-pair',
        values: {...rows[1].values, 'state': 'failed'},
      );
      final sample = sampler.sample(rows);
      expect(sample.selectedPairState, CallSelectedPairState.failed);
      expect(sample.selectedPairSucceeded, isFalse);
      expect(sample.selectedLocalCandidateFamily, CallAddressFamily.ipv4);
      expect(sample.inboundAudioRtpObserved, isFalse);
    },
  );

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
        'remoteCandidateId': 'remote',
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

  test(
    'native TURN-backed prflx uses only the selected local relayProtocol',
    () {
      for (final entry in {
        'udp': CallTransportClass.turnUdp,
        'tcp': CallTransportClass.turnTcpTls,
        'tls': CallTransportClass.turnTcpTls,
      }.entries) {
        final sample = sampler.sample(
          selectedPair(
            candidateType: 'prflx',
            protocol: 'udp',
            relayProtocol: entry.key,
          ),
        );
        expect(sample.transport, entry.value);
        expect(sample.selectedRelayProtocol.name, entry.key);
      }
      for (final protocol in [null, '', 'quic']) {
        final sample = sampler.sample(
          selectedPair(
            candidateType: 'prflx',
            protocol: 'udp',
            relayProtocol: protocol,
          ),
        );
        expect(sample.transport, CallTransportClass.direct);
        expect(sample.selectedRelayProtocol, CallRelayProtocol.notRelay);
      }
    },
  );

  test(
    'a remote relay never proves that the selected local side is relayed',
    () {
      for (final localType in ['host', 'srflx', 'prflx', 'relay', null]) {
        final records = selectedPair(
          candidateType: localType,
          protocol: 'udp',
          relayProtocol: localType == 'relay' ? 'udp' : null,
          includeLocalCandidate: localType != null,
        );
        records.add(
          const CallStatsRecord(
            id: 'remote',
            type: 'remote-candidate',
            values: {'candidateType': 'relay', 'protocol': 'udp'},
          ),
        );
        final sample = sampler.sample(records);
        expect(
          sample.transport,
          localType == null
              ? CallTransportClass.unknown
              : localType == 'relay'
              ? CallTransportClass.turnUdp
              : CallTransportClass.direct,
        );
      }
    },
  );

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
