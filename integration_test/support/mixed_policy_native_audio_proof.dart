import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/features/call/domain/call_engine.dart';
import 'package:flutter_app/features/call/infrastructure/flutter_webrtc_call_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
// The pinned plugin already uses this logger; this fixture adds no runtime pin.
// ignore: depend_on_referenced_packages
import 'package:logger/logger.dart';

/// Optional two-device extension of the existing real-adapter integration test.
/// The loopback broker carries synthetic test SDP/ICE in memory. Authentication
/// and call ownership are exercised separately by call_remote_ice_drain_test.
/// No raw SDP, addresses, native stats, or TURN credentials enter proof results.
void registerMixedPolicyNativeAudioProof() {
  const broker = String.fromEnvironment('MIXED_POLICY_BROKER');
  if (broker.isEmpty) return;
  test('native mixed policy matrix, both directions and ICE restart', () async {
    final wire = _ProofWire(broker);
    addTearDown(wire.close);
    final config = await wire.get('config');
    final side = config['side']! as int;
    final tlsLog = _NativeTlsLog();
    rtc.Helper.setLogger(
      Logger(printer: SimplePrinter(printTime: false), output: tlsLog),
      'info',
    );
    await rtc.WebRTC.initialize(options: {'logSeverity': 'info'});
    final policies = config['relayOnly'] == true
        ? [CallTransportPolicy.relayOnly]
        : CallTransportPolicy.values;
    final rejectedTls = config['expectedTlsRejection'] as String?;
    final negativeControls = <Map<String, Object?>>[];
    var closedCalls = 0;
    _TurnUdpBlackhole? udpBlackhole;
    if (config['unavailableTurnUdp'] != null) {
      udpBlackhole = await _TurnUdpBlackhole.start();
      addTearDown(udpBlackhole.close);
    }
    final hostnameProbe = config['turnHostnameProbe'] == true;
    _Ipv4TurnProxy? turnProxy;
    final dnsFamilies = <String>[];
    if (hostnameProbe) {
      turnProxy = await _Ipv4TurnProxy.start();
      addTearDown(turnProxy.close);
      // Android's hosts file maps localhost to IPv4 only. This public test
      // name supplies both loopbacks; reject any non-loopback DNS response.
      final addresses = await InternetAddress.lookup('localtest.me');
      expect(
        addresses.every((a) => a.address == '127.0.0.1' || a.address == '::1'),
        isTrue,
      );
      dnsFamilies.addAll(
        addresses
            .map((a) => a.type == InternetAddressType.IPv6 ? 'ipv6' : 'ipv4')
            .toSet(),
      );
      expect(dnsFamilies, containsAll(['ipv4', 'ipv6']));
      // DNS answers alone do not establish allocation. This fixture accepts
      // TURN/TCP only on IPv4; explicitly establish that its IPv6 socket fails.
      await expectLater(
        Socket.connect(
          InternetAddress.loopbackIPv6,
          34793,
          timeout: const Duration(seconds: 2),
        ).then((socket) {
          socket.destroy();
          throw StateError('unexpected IPv6 TURN listener');
        }),
        throwsA(isA<SocketException>()),
      );
    }
    List<CallIceServer> serversFrom(Map<String, Object?> credentials) => [
      CallIceServer(
        urls: [
          if (credentials['stun'] case final String stun) stun,
          if (config['unavailableTurnUdp'] case final String unavailable)
            unavailable,
          hostnameProbe
              ? 'turn:localtest.me:34793?transport=tcp'
              : credentials['turn']! as String,
        ],
        username: credentials['username']! as String,
        credential: credentials['credential']! as String,
        expiresAt: switch (credentials['expiresAtMs']) {
          final int expiresAtMs => DateTime.fromMillisecondsSinceEpoch(
            expiresAtMs,
            isUtc: true,
          ),
          _ => DateTime.now().toUtc().add(const Duration(hours: 1)),
        },
      ),
    ];
    final results = <Map<String, Object?>>[];
    for (final a in policies) {
      for (final b in policies) {
        for (final caller in [0, 1]) {
          final name = '${a.name}-${b.name}-$caller';
          final localPolicy = side == 0 ? a : b;
          final servers = serversFrom(
            config['perCallCredentials'] == true
                ? await wire.get('credentials/$name')
                : config,
          );
          expect(
            servers.single.expiresAt.isAfter(DateTime.now().toUtc()),
            isTrue,
          );
          if (config['requiredTurnDnsFamily'] case final String family) {
            final hostname = config['turnHostname']! as String;
            expect(
              servers.single.urls.single,
              switch (config['expectedRelayProtocol']) {
                'udp' => 'turn:$hostname:3478?transport=udp',
                'tls' => 'turns:$hostname:5349?transport=tcp',
                _ => throw StateError('Family proof requires UDP or TLS'),
              },
            );
            final addresses = await InternetAddress.lookup(hostname);
            expect(addresses, isNotEmpty);
            expect(
              addresses
                  .map(
                    (a) => a.type == InternetAddressType.IPv6 ? 'ipv6' : 'ipv4',
                  )
                  .toSet(),
              {family},
              reason: 'Only the isolated TURN connection family may resolve',
            );
          }
          final peer = _NativePeer(localPolicy, servers);
          try {
            tlsLog.reset();
            await peer.create();
            await wire.exchange('$name/created', {});
            if (rejectedTls != null) {
              expect(localPolicy, CallTransportPolicy.relayOnly);
              expect(servers.single.urls.length, 1);
              expect(servers.single.urls.single.startsWith('turns:'), isTrue);
              await peer.localDescription(offer: true);
              await _until(() async => tlsLog.rejected(rejectedTls));
              // A connection timeout or lack of candidates alone is not a
              // certificate rejection. Require the specific native TLS event.
              expect(peer.raw, isEmpty);
              expect(
                (await peer.engine.snapshot()).selectedPairSucceeded,
                isFalse,
              );
              negativeControls.add({'reason': rejectedTls, 'rejected': true});
            }
            for (final generation in rejectedTls == null ? [0, 1] : <int>[]) {
              if (generation == 1) {
                await peer.engine.restartIce(iceServers: servers);
                peer.clearCandidates();
                await wire.exchange('$name/restarted', {});
              }
              final phase = '$name/$generation';
              peer.beginPhase();
              if (side == caller) {
                final offer = await peer.localDescription(offer: true);
                await wire.post('$phase/offer', offer);
                peer.localDescriptionSent();
                await peer.remoteDescription(await wire.get('$phase/answer'));
              } else {
                await peer.remoteDescription(await wire.get('$phase/offer'));
                await wire.post(
                  '$phase/answer',
                  await peer.localDescription(offer: false),
                );
                peer.localDescriptionSent();
              }
              if (config['brokenIpv6Candidate'] == true) {
                await peer.addBrokenIpv6Candidate(generation);
              }
              await peer.exchangeCandidates(wire, phase);
              await peer.waitForMedia();
              final result = await peer.verify(generation);
              if (config['relayOnly'] == true) {
                expect(
                  result['localRelayProtocol'],
                  config['expectedRelayProtocol'],
                );
              }
              result['platformChainValidations'] = tlsLog.validations;
              result.addAll({'case': name, 'generation': generation});
              results.add(result);
              await wire.exchange('$phase/verified', result);
            }
          } catch (_) {
            await wire.post('result', {
              'passed': false,
              'failedCase': name,
              'phases': results,
              'native': await peer.failureStats(),
            });
            rethrow;
          } finally {
            await peer.close();
          }
          // Each subsequent case creates fresh wrappers after both endpoints
          // closed; no candidate subscription or peer is reused across calls.
          await wire.exchange('$name/closed', {'closed': peer.engine.isClosed});
          expect(peer.engine.isClosed, isTrue);
          closedCalls++;
        }
      }
    }
    if (udpBlackhole != null) expect(udpBlackhole.dropped, greaterThan(0));
    if (turnProxy != null) expect(turnProxy.connections, greaterThan(0));
    await wire.post('result', {
      'passed': true,
      'phases': results,
      'closedCalls': closedCalls,
      'negativeControls': negativeControls,
      'turnHostnameDnsFamilies': dnsFamilies,
      'turnHostnameIpv6SocketUnavailable': hostnameProbe,
      'turnIpv4ProxyConnections': turnProxy?.connections,
      'turnUdpDatagramsDropped': udpBlackhole?.dropped,
    });
  }, timeout: const Timeout(Duration(minutes: 12)));
}

/// Reduce native logs to fixed TLS outcomes before anything is printed or
/// retained. Do not retain certificate subjects, sockets, SDP or credentials.
final class _NativeTlsLog extends LogOutput {
  var validations = 0;
  var chainRejections = 0;
  var hostnameRejections = 0;

  void reset() {
    validations = chainRejections = hostnameRejections = 0;
  }

  bool rejected(String reason) => switch (reason) {
    'untrusted' => chainRejections > 0,
    'hostname' => validations > 0 && hostnameRejections > 0,
    _ => false,
  };

  @override
  void output(OutputEvent event) {
    for (final line in event.lines) {
      if (line.contains('Validated certificate chain using custom callback')) {
        validations++;
      }
      if (line.contains(
        'Peer certificate chain was rejected by the platform trust store',
      )) {
        chainRejections++;
      }
      if (line.contains('TLS post connection check failed')) {
        hostnameRejections++;
      }
    }
  }
}

/// A scoped TURN/UDP blackhole: datagrams reach this fixture and receive no
/// response. TURN/TCP remains available on its separate configured endpoint.
final class _TurnUdpBlackhole {
  _TurnUdpBlackhole(this.socket) {
    socket.listen((event) {
      if (event == RawSocketEvent.read) {
        while (socket.receive() != null) {
          dropped++;
        }
      }
    });
  }

  final RawDatagramSocket socket;
  var dropped = 0;
  static Future<_TurnUdpBlackhole> start() async => _TurnUdpBlackhole(
    await RawDatagramSocket.bind(
      InternetAddress.loopbackIPv4,
      34792,
      reuseAddress: false,
    ),
  );
  void close() => socket.close();
}

/// A test-local IPv4-only TCP endpoint for the existing USB TURN fixture.
/// It owns only its bound socket and accepted connections, and never logs bytes.
final class _Ipv4TurnProxy {
  _Ipv4TurnProxy(this.server) {
    server.listen((socket) {
      final task = _forward(socket);
      pending.add(task);
      unawaited(task.whenComplete(() => pending.remove(task)));
    });
  }

  final ServerSocket server;
  final sockets = <Socket>{};
  final pending = <Future<void>>{};
  var closed = false;
  var connections = 0;

  static Future<_Ipv4TurnProxy> start() async => _Ipv4TurnProxy(
    await ServerSocket.bind(InternetAddress.loopbackIPv4, 34793),
  );

  Future<void> _forward(Socket client) async {
    sockets.add(client);
    Socket? upstream;
    try {
      upstream = await Socket.connect(
        InternetAddress.loopbackIPv4,
        34791,
        timeout: const Duration(seconds: 2),
      );
      sockets.add(upstream);
      if (closed) return;
      connections++;
      await Future.wait([
        client.cast<List<int>>().pipe(upstream),
        upstream.cast<List<int>>().pipe(client),
      ]);
    } on SocketException {
      // Native TURN may close an unused allocation/connection on restart.
    } finally {
      sockets.remove(client);
      sockets.remove(upstream);
      client.destroy();
      upstream?.destroy();
    }
  }

  Future<void> close() async {
    closed = true;
    await server.close();
    for (final socket in sockets.toList()) {
      socket.destroy();
    }
    await Future.wait(pending.toList());
  }
}

final class _NativePeer {
  _NativePeer(this.policy, this.servers) {
    adapter = FlutterWebRtcPeerConnectionAdapter(
      peerConnectionFactory: (configuration) async {
        native = await rtc.createPeerConnection(configuration);
        return native;
      },
    );
    engine = FlutterWebRtcCallEngine(adapter: adapter);
    subscriptions.add(adapter.localCandidates.listen(raw.add));
    subscriptions.add(engine.localCandidates.listen(outbound.add));
  }

  final CallTransportPolicy policy;
  final List<CallIceServer> servers;
  late final FlutterWebRtcPeerConnectionAdapter adapter;
  late final FlutterWebRtcCallEngine engine;
  late final rtc.RTCPeerConnection native;
  final raw = <CallIceCandidate>[];
  final outbound = <CallIceCandidate>[];
  final subscriptions = <StreamSubscription<CallIceCandidate>>[];
  final descriptions = <String>[];
  final phaseClock = Stopwatch();
  String? previousUfrag;
  int? localSdpSentMs;
  bool? localSdpSentBeforeGatheringComplete;
  int? gatheringCompleteMs;

  void beginPhase() {
    phaseClock
      ..reset()
      ..start();
    localSdpSentMs = null;
    localSdpSentBeforeGatheringComplete = null;
    gatheringCompleteMs = null;
  }

  bool get gatheringComplete =>
      raw.any((candidate) => candidate.iceGeneration == engine.iceGeneration) &&
      native.iceGatheringState ==
          rtc.RTCIceGatheringState.RTCIceGatheringStateComplete;

  void localDescriptionSent() {
    localSdpSentMs = phaseClock.elapsedMilliseconds;
    localSdpSentBeforeGatheringComplete = !gatheringComplete;
  }

  Future<void> create() => engine.createConnection(
    CallConnectionConfiguration(
      transportPolicy: policy,
      receiveAudio: true,
      receiveVideo: false,
      captureAudio: true,
      captureVideo: false,
      iceServers: servers,
    ),
  );

  void clearCandidates() {
    raw.clear();
    outbound.clear();
    descriptions.clear();
  }

  Future<Map<String, Object?>> localDescription({required bool offer}) async {
    final description = await (offer
        ? engine.createOffer()
        : engine.createAnswer());
    descriptions.add(description.value);
    final ufrag = RegExp(
      r'a=ice-ufrag:([^\r\n]+)',
    ).firstMatch(description.value)!.group(1)!;
    if (engine.iceGeneration > 0) expect(ufrag == previousUfrag, isFalse);
    previousUfrag = ufrag;
    await engine.setLocalDescription(description);
    // Match production signaling: publish SDP immediately, then trickle ICE.
    // Waiting for UDP gathering here can outlast ICE's connectivity deadline
    // on the answerer before the caller has received any answer at all.
    await _verifyEgress(requireCompleteGathering: false);
    return {
      'sdp': description.value,
      'type': description.type.name,
      'fingerprint': description.fingerprint,
    };
  }

  Future<void> remoteDescription(Map<String, Object?> message) async {
    await engine.setRemoteDescription(
      CallSessionDescription(
        type: CallSessionDescriptionType.values.byName(
          message['type']! as String,
        ),
        value: message['sdp']! as String,
        fingerprint: message['fingerprint']! as String,
      ),
    );
  }

  Future<void> exchangeCandidates(_ProofWire wire, String phase) async {
    var sent = 0;
    var round = 0;
    // Native UDP gathering was observed taking about 40 seconds even with
    // working media. Give this independent audit margin; SDP has already been
    // published and connectivity checks are progressing during the wait.
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    while (true) {
      final batch = outbound
          .skip(sent)
          .take(engine.candidateBatchCapacity)
          .toList();
      final localComplete =
          gatheringComplete && sent + batch.length == outbound.length;
      if (gatheringComplete) {
        gatheringCompleteMs ??= phaseClock.elapsedMilliseconds;
      }
      // Validate before sending this snapshot; later arrivals belong to a
      // subsequent round. Both peers POST even empty batches before waiting.
      await _verifyEgress(requireCompleteGathering: false);
      await wire.post('$phase/ice/$round', {
        'complete': localComplete,
        'candidates': [
          for (final c in batch)
            {
              'value': c.value,
              'mid': c.mediaId,
              'line': c.mediaLineIndex,
              'generation': c.iceGeneration,
            },
        ],
      });
      sent += batch.length;
      final remote = await wire.get('$phase/ice/$round');
      await _remoteCandidates(remote['candidates']! as List);
      if (localComplete && remote['complete'] == true) break;
      if (DateTime.now().isAfter(deadline)) {
        throw StateError('native ICE gathering/exchange deadline exceeded');
      }
      round += 1;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    // Native gathered SDP is audited independently after signaling has already
    // progressed. Full-gather batching must never delay an offer or answer.
    descriptions.add((await native.getLocalDescription())!.sdp!);
    await _verifyEgress();
  }

  Future<void> addBrokenIpv6Candidate(int generation) async {
    // Documentation space cannot provide a working path. Keep every native
    // direct/STUN/TURN candidate in flight alongside this controlled bad input.
    await engine.addIceCandidates([
      CallIceCandidate(
        value:
            'candidate:broken6 1 udp 2122260223 2001:db8::bad 49999 typ host',
        mediaId: '0',
        mediaLineIndex: 0,
        iceGeneration: generation,
      ),
    ]);
  }

  Future<void> _remoteCandidates(List<dynamic> candidates) async {
    for (final item in candidates) {
      final c = item as Map;
      await engine.addIceCandidates([
        CallIceCandidate(
          value: c['value'] as String,
          mediaId: c['mid'] as String?,
          mediaLineIndex: c['line'] as int?,
          iceGeneration: c['generation'] as int,
        ),
      ]);
    }
  }

  Future<void> waitForMedia() async {
    await _until(() async {
      final snapshot = await engine.snapshot();
      return snapshot.selectedPairSucceeded &&
          snapshot.selectedPairNominated &&
          snapshot.dtlsReady &&
          snapshot.inboundAudioRtpObserved &&
          snapshot.outboundAudioRtpObserved;
    });
    final before = await _rtpCounters();
    await _until(() async {
      final after = await _rtpCounters();
      return after.$1 > before.$1 && after.$2 > before.$2;
    });
  }

  Future<(int, int)> _rtpCounters() async {
    var inbound = 0;
    var outbound = 0;
    for (final row in await native.getStats()) {
      if (row.values['kind'] != 'audio') continue;
      if (row.type == 'inbound-rtp') {
        inbound += (row.values['bytesReceived'] as num?)?.toInt() ?? 0;
      }
      if (row.type == 'outbound-rtp') {
        outbound += (row.values['bytesSent'] as num?)?.toInt() ?? 0;
      }
    }
    return (inbound, outbound);
  }

  Future<Map<String, Object?>> verify(int generation) async {
    await _verifyEgress();
    var stats = <rtc.StatsReport>[];
    // ICE can change selected pairs between readiness and this independent
    // native read. Wait for a complete selected-pair observation within the
    // same bounded phase instead of interpreting an in-progress pair as ready.
    await _until(() async {
      stats = await native.getStats();
      final byId = {for (final row in stats) row.id: row};
      for (final row in stats.where((r) => r.type == 'transport')) {
        final pair = byId[row.values['selectedCandidatePairId']];
        if (pair?.values['state'] == 'succeeded' &&
            byId[pair?.values['localCandidateId']]?.type == 'local-candidate' &&
            byId[pair?.values['remoteCandidateId']]?.type ==
                'remote-candidate') {
          return true;
        }
      }
      return false;
    });
    final byId = {for (final r in stats) r.id: r};
    final transport = stats.firstWhere(
      (r) =>
          r.type == 'transport' && r.values['selectedCandidatePairId'] != null,
    );
    final pair = byId[transport.values['selectedCandidatePairId']]!;
    final local = byId[pair.values['localCandidateId']]!;
    final remote = byId[pair.values['remoteCandidateId']]!;
    expect(local.type, 'local-candidate');
    expect(pair.values['state'], 'succeeded');
    final localUsesTurn =
        local.values['candidateType'] == 'relay' ||
        (local.values['candidateType'] == 'prflx' &&
            const {
              'udp',
              'tcp',
              'tls',
            }.contains(local.values['relayProtocol']));
    if (policy == CallTransportPolicy.relayOnly) {
      expect(
        localUsesTurn,
        isTrue,
        reason: 'selected local native transport must retain TURN provenance',
      );
    }
    expect(outbound.every((c) => c.iceGeneration == generation), isTrue);
    final snapshot = await engine.snapshot();
    expect(snapshot.transportPolicy, policy);
    return {
      'policy': policy.name,
      'localSdpSentMs': localSdpSentMs,
      'localSdpSentBeforeGatheringComplete':
          localSdpSentBeforeGatheringComplete,
      'gatheringCompleteMs': gatheringCompleteMs,
      'rawCandidateCount': raw.length,
      'outboundCandidateCount': outbound.length,
      'rawCandidateTypes': _candidateTypeCounts(raw),
      'outboundCandidateTypes': _candidateTypeCounts(outbound),
      'localCandidateType': local.values['candidateType'],
      'localUsesTurn': localUsesTurn,
      'localRelayProtocol': local.values['relayProtocol'],
      'remoteCandidateType': remote.values['candidateType'],
      'selectedLocalFamily': _family(local.values),
      'selectedRemoteFamily': _family(remote.values),
      'secureTransportReady': snapshot.dtlsReady,
      // Admission is separate from evidence that native ICE actually attempted
      // a bad pair. Preserve both without retaining raw candidate addresses.
      'brokenIpv6RemoteObserved': stats.any(
        (r) =>
            r.type == 'remote-candidate' &&
            (r.values['address'] ?? r.values['ip']) == '2001:db8::bad',
      ),
      'brokenIpv6RequestsSent': stats
          .where(
            (r) =>
                r.type == 'candidate-pair' &&
                (byId[r.values['remoteCandidateId']]?.values['address'] ??
                        byId[r.values['remoteCandidateId']]?.values['ip']) ==
                    '2001:db8::bad',
          )
          .fold<int>(
            0,
            (sum, r) =>
                sum + ((r.values['requestsSent'] as num?)?.toInt() ?? 0),
          ),
      'relatedAddressesSanitized': policy == CallTransportPolicy.relayOnly,
      'sdpAndCandidatePrivacyChecked': policy == CallTransportPolicy.relayOnly,
      'bidirectionalRtpAdvanced': true,
      'transport': snapshot.transport.name,
    };
  }

  static String _family(Map<dynamic, dynamic> values) {
    final address = values['address'] ?? values['ip'];
    if (address is! String) return 'unknown';
    return InternetAddress.tryParse(address)?.type == InternetAddressType.IPv6
        ? 'ipv6'
        : InternetAddress.tryParse(address)?.type == InternetAddressType.IPv4
        ? 'ipv4'
        : 'unknown';
  }

  Future<Map<String, Object?>> failureStats() async {
    try {
      final stats = await native.getStats();
      final byId = {for (final row in stats) row.id: row};
      return {
        'connectionState': native.connectionState?.name,
        'localSdpSentMs': localSdpSentMs,
        'localSdpSentBeforeGatheringComplete':
            localSdpSentBeforeGatheringComplete,
        'gatheringCompleteMs': gatheringCompleteMs,
        'pairs': [
          for (final row in stats.where((r) => r.type == 'candidate-pair'))
            {
              'state': row.values['state'],
              'localType':
                  byId[row.values['localCandidateId']]?.values['candidateType'],
              'localRelayProtocol':
                  byId[row.values['localCandidateId']]?.values['relayProtocol'],
              'remoteType': byId[row.values['remoteCandidateId']]
                  ?.values['candidateType'],
              for (final key in [
                'requestsSent',
                'requestsReceived',
                'responsesReceived',
                'bytesSent',
                'bytesReceived',
              ])
                key: row.values[key],
            },
        ],
      };
    } catch (_) {
      return {'statisticsAvailable': false};
    }
  }

  Future<void> _verifyEgress({bool requireCompleteGathering = true}) async {
    if (policy != CallTransportPolicy.relayOnly) {
      if (!requireCompleteGathering) return;
      expect(
        _candidateTypeCounts(
          outbound,
        ).keys.any((type) => const {'host', 'srflx', 'prflx'}.contains(type)),
        isTrue,
        reason: 'normal peers must supply real non-relay candidates',
      );
      return;
    }
    if (requireCompleteGathering) {
      expect(raw.isNotEmpty, isTrue);
      expect(
        outbound.map((c) => c.value),
        orderedEquals(raw.map((c) => c.value)),
      );
    }
    final relayAddresses = <String>{};
    void candidate(String value) {
      final tokens = value
          .replaceFirst(RegExp(r'^a='), '')
          .split(RegExp(r'\s+'));
      expect(tokens[7], 'relay');
      relayAddresses.add(tokens[4]);
      for (var i = 8; i + 1 < tokens.length; i += 2) {
        if (tokens[i] == 'raddr') {
          expect({'0.0.0.0', '::'}.contains(tokens[i + 1]), isTrue);
        }
        if (tokens[i] == 'rport') expect(tokens[i + 1], '0');
      }
    }

    for (final c in raw) {
      candidate(c.value);
    }
    for (final sdp in descriptions) {
      for (final line in const LineSplitter().convert(sdp)) {
        if (line.startsWith('a=candidate:')) candidate(line);
      }
      for (final line in const LineSplitter().convert(sdp)) {
        if (line.startsWith('o=') ||
            line.startsWith('c=') ||
            line.startsWith('a=rtcp:')) {
          final fields = line.split(' ');
          if (fields.length < 3) continue;
          expect(
            {
              '0.0.0.0',
              '::',
              '127.0.0.1',
              '::1',
              ...relayAddresses,
            }.contains(fields.last),
            isTrue,
            reason: 'SDP address must be a placeholder or a gathered relay',
          );
        }
      }
    }
    final ownAddresses = [
      for (final interface in await NetworkInterface.list())
        for (final address in interface.addresses)
          if (!address.isLoopback && !relayAddresses.contains(address.address))
            address.address,
    ];
    final signaled = [
      ...descriptions,
      ...outbound.map((c) => c.value),
    ].join('\n');
    for (final address in ownAddresses) {
      expect(
        signaled.contains(address),
        isFalse,
        reason: 'direct interface address in media signaling',
      );
    }
  }

  Future<void> close() async {
    await engine.close();
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
  }
}

Map<String, int> _candidateTypeCounts(Iterable<CallIceCandidate> candidates) {
  final counts = <String, int>{};
  for (final candidate in candidates) {
    final tokens = candidate.value.split(RegExp(r'\s+'));
    final type = tokens.length >= 8 ? tokens[7] : 'unknown';
    expect(const {'host', 'srflx', 'prflx', 'relay'}.contains(type), isTrue);
    counts.update(type, (count) => count + 1, ifAbsent: () => 1);
  }
  return counts;
}

Future<void> _until(Future<bool> Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 40));
  while (!await ready()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('native proof deadline exceeded');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

final class _ProofWire {
  _ProofWire(this.base);
  final String base;
  final client = HttpClient();
  Future<Map<String, Object?>> get(String path) => _request('GET', path);
  Future<void> post(String path, Map<String, Object?> value) async {
    await _request('POST', path, value);
  }

  Future<void> exchange(String path, Map<String, Object?> value) async {
    await post(path, value);
    await get(path);
  }

  Future<Map<String, Object?>> _request(
    String method,
    String path, [
    Map<String, Object?>? value,
  ]) async {
    final request = await client.openUrl(method, Uri.parse('$base/$path'));
    if (value != null) {
      final body = utf8.encode(jsonEncode(value));
      request.headers.contentType = ContentType.json;
      request.contentLength = body.length;
      request.add(body);
    }
    final response = await request.close().timeout(const Duration(seconds: 60));
    if (response.statusCode != 200) throw StateError('proof broker failed');
    return (jsonDecode(await utf8.decoder.bind(response).join()) as Map)
        .cast<String, Object?>();
  }

  void close() => client.close(force: true);
}
