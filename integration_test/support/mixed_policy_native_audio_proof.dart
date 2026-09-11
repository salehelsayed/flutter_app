import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/features/call/domain/call_engine.dart';
import 'package:flutter_app/features/call/infrastructure/flutter_webrtc_call_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;

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
    final servers = [
      CallIceServer(
        urls: [
          if (config['stun'] case final String stun) stun,
          config['turn']! as String,
        ],
        username: config['username']! as String,
        credential: config['credential']! as String,
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      ),
    ];
    final results = <Map<String, Object?>>[];
    for (final a in CallTransportPolicy.values) {
      for (final b in CallTransportPolicy.values) {
        for (final caller in [0, 1]) {
          final name = '${a.name}-${b.name}-$caller';
          final localPolicy = side == 0 ? a : b;
          final peer = _NativePeer(localPolicy, servers);
          try {
            await peer.create();
            await wire.exchange('$name/created', {});
            for (final generation in [0, 1]) {
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
              await peer.exchangeCandidates(wire, phase);
              await peer.waitForMedia();
              final result = await peer.verify(generation);
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
        }
      }
    }
    await wire.post('result', {'passed': true, 'phases': results});
  }, timeout: const Timeout(Duration(minutes: 12)));
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
      'relatedAddressesSanitized': policy == CallTransportPolicy.relayOnly,
      'sdpAndCandidatePrivacyChecked': policy == CallTransportPolicy.relayOnly,
      'bidirectionalRtpAdvanced': true,
      'transport': snapshot.transport.name,
    };
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
