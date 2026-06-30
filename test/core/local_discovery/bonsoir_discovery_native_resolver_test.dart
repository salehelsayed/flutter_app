// 180: the Android-only native mDNS resolver, composed into BonsoirDiscoveryService.
//
// On Android, NsdManager (upstream bonsoir_android) intermittently never completes
// an iOS `.local`-hostname _mknoon._tcp service, so the Pixel never resolves the
// iPhone. The native resolver does its own PTR→SRV→TXT→A over a MulticastSocket
// (IP_MULTICAST_IF=wlan0); these tests lock the DART wiring — that native-resolved
// peers feed the SAME _commitResolvedPeer → _buildLibp2pAddresses(numeric→/ip4) →
// _peers/_peersController/_pendingResolves chain as bonsoir-resolved peers, with
// dedup, a platform gate, lifecycle, and resolvePeer/refresh parity. The native
// multicast leg itself is host-unfakeable → device-proof TC-180-07.

import 'dart:async';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride, TargetPlatform;
import 'package:flutter_app/core/local_discovery/bonsoir_discovery_service.dart';
import 'package:flutter_app/core/local_discovery/local_discovery_service.dart';
import 'package:flutter_app/core/local_discovery/native_mdns_resolver.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_native_mdns_resolver.dart';

void main() {
  group('BonsoirDiscoveryService native resolver (180)', () {
    late List<_FakeBonsoirBroadcast> broadcasts;
    late List<_FakeBonsoirDiscovery> discoveries;
    late FakeNativeMdnsResolver native;
    late BonsoirDiscoveryService service;
    late List<Map<String, dynamic>> events;

    _FakeBonsoirDiscovery discovery() => discoveries.last;

    BonsoirDiscoveryService build({FakeNativeMdnsResolver? withNative}) {
      return BonsoirDiscoveryService(
        createBroadcast: (s) {
          final f = _FakeBonsoirBroadcast(s);
          broadcasts.add(f);
          return f;
        },
        createDiscovery: (t) {
          final f = _FakeBonsoirDiscovery(t);
          discoveries.add(f);
          return f;
        },
        nativeResolver: withNative ?? native,
      );
    }

    setUp(() {
      broadcasts = <_FakeBonsoirBroadcast>[];
      discoveries = <_FakeBonsoirDiscovery>[];
      native = FakeNativeMdnsResolver();
      events = <Map<String, dynamic>>[];
      debugSetFlowEventSink(events.add);
      // Android is the affected platform (the native resolver runs there).
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      service = build();
    });

    tearDown(() async {
      await service.stopAdvertising(); // cancels the 20s refresh Timer.periodic
      native.dispose();
      debugSetFlowEventSink(null);
      debugDefaultTargetPlatformOverride = null;
    });

    Future<void> flush() => Future<void>.delayed(const Duration(milliseconds: 10));

    NativeResolvedPeer iphone({String host = '192.168.0.211'}) =>
        NativeResolvedPeer(
          peerId: 'iphone',
          host: host,
          port: 1,
          attributes: const {'quicPort': '4001', 'tcpPort': '4002'},
        );

    // TC-180-01/02
    test(
      'a native-resolved peer (numeric host + ports) becomes a LocalPeer with '
      '/ip4 addresses and LOCAL_MDNS_PEER_FOUND',
      () async {
        await service.startAdvertising('me-peer', 54321);
        native.emit(iphone());
        await flush();

        final peer = service.discoveredPeers['iphone'];
        expect(peer, isNotNull);
        expect(peer!.host, '192.168.0.211');
        expect(
          peer.libp2pAddresses,
          containsAll(<String>[
            '/ip4/192.168.0.211/udp/4001/quic-v1',
            '/ip4/192.168.0.211/tcp/4002',
          ]),
        );
        expect(
          events.where(
            (e) =>
                e['event'] == 'LOCAL_MDNS_PEER_FOUND' &&
                (e['details'] as Map)['peerId'] == 'iphone',
          ),
          hasLength(1),
        );
      },
    );

    // TC-180-02 (stream)
    test('a native-resolved peer is emitted on discoveredPeersStream', () async {
      await service.startAdvertising('me-peer', 54321);
      final emissions = <Map<String, LocalPeer>>[];
      final sub = service.discoveredPeersStream.listen(emissions.add);

      native.emit(iphone());
      await flush();

      expect(
        emissions.any(
          (m) => m['iphone'] != null && m['iphone']!.libp2pAddresses.isNotEmpty,
        ),
        isTrue,
      );
      await sub.cancel();
    });

    // TC-180-03
    test(
      'a native-resolved and a bonsoir-resolved peer for the SAME peerId '
      'collapse to ONE entry',
      () async {
        await service.startAdvertising('me-peer', 54321);
        native.emit(iphone());
        await flush();
        // The native path committed the peer (RED on HEAD: it is not wired, so
        // discoveredPeers is empty here — this is what fails before the fix).
        expect(
          service.discoveredPeers,
          hasLength(1),
          reason: 'native resolver committed the peer',
        );
        expect(service.discoveredPeers['iphone']!.libp2pAddresses, isNotEmpty);

        // A bonsoir resolve for the SAME peerId must collapse to ONE entry.
        discovery().emit(
          _resolvedEvent(
            'iphone',
            host: '192.168.0.211',
            port: 1,
            quicPort: 4001,
          ),
        );
        await flush();

        expect(service.discoveredPeers, hasLength(1), reason: 'deduped by peerId');
        expect(service.discoveredPeers.containsKey('iphone'), isTrue);
      },
    );

    // TC-180-04
    test('platform gate — the native resolver is NOT started on iOS', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await service.startAdvertising('me-peer', 54321);
      expect(
        native.startCallCount,
        0,
        reason: 'native resolver must never start on iOS',
      );

      // On Android it IS started.
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final native2 = FakeNativeMdnsResolver();
      final svc2 = build(withNative: native2);
      await svc2.startAdvertising('me-peer', 54321);
      expect(native2.startCallCount, 1);
      await svc2.stopAdvertising();
      native2.dispose();
    });

    // TC-180-05
    test(
      'native resolver lifecycle — started on advertise, stopped on '
      'stopAdvertising, re-subscribes on restart',
      () async {
        await service.startAdvertising('me-peer', 54321);
        expect(native.startCallCount, 1);

        await service.stopAdvertising();
        expect(native.stopCallCount, 1);

        await service.startAdvertising('me-peer', 54321);
        expect(
          native.startCallCount,
          2,
          reason: 're-subscribe on restart, no leaked subscription',
        );
      },
    );

    // TC-180-06
    test('resolvePeer (discover-on-send) completes from a native-resolved peer',
        () async {
      await service.startAdvertising('me-peer', 54321);
      final pending =
          service.resolvePeer('iphone', timeout: const Duration(seconds: 2));
      await flush();
      native.emit(iphone());

      final peer = await pending;
      expect(peer, isNotNull);
      expect(peer!.peerId, 'iphone');
      expect(peer.libp2pAddresses, isNotEmpty);
    });

    // TC-180-09
    test(
      're-emitting a native-resolved peer refreshes it (native peers get the '
      'same freshness as bonsoir peers)',
      () async {
        await service.startAdvertising('me-peer', 54321);
        native.emit(iphone());
        await flush();
        final first = service.discoveredPeers['iphone']!.discoveredAt;

        await Future<void>.delayed(const Duration(milliseconds: 20));
        native.emit(iphone());
        await flush();
        final second = service.discoveredPeers['iphone']!.discoveredAt;

        expect(
          second.isAfter(first),
          isTrue,
          reason: 'a native re-resolve refreshes discoveredAt',
        );
      },
    );
  });
}

// --- bonsoir fakes (mirror the contract test) ----------------------------------

BonsoirDiscoveryEvent _resolvedEvent(
  String peerId, {
  required String? host,
  required int port,
  int? quicPort,
  int? tcpPort,
}) {
  return BonsoirDiscoveryEvent(
    type: BonsoirDiscoveryEventType.discoveryServiceResolved,
    service: ResolvedBonsoirService(
      name: 'mknoon',
      type: '_mknoon._tcp',
      port: port,
      attributes: {
        'peerId': peerId,
        if (quicPort != null) 'quicPort': '$quicPort',
        if (tcpPort != null) 'tcpPort': '$tcpPort',
      },
      host: host,
    ),
  );
}

class _RecordingResolver with ServiceResolver {
  final resolved = <BonsoirService>[];

  @override
  Future<void> resolveService(BonsoirService service) async {
    resolved.add(service);
  }
}

class _FakeBonsoirDiscovery implements BonsoirDiscovery {
  @override
  final String type;
  final resolver = _RecordingResolver();
  final _controller = StreamController<BonsoirDiscoveryEvent>.broadcast();
  int startCalls = 0;
  int stopCalls = 0;

  _FakeBonsoirDiscovery(this.type);

  void emit(BonsoirDiscoveryEvent event) {
    if (!_controller.isClosed) _controller.add(event);
  }

  @override
  ServiceResolver get serviceResolver => resolver;
  @override
  Future<void> get ready async {}
  @override
  bool get isReady => true;
  @override
  bool get isStopped => stopCalls > 0;
  @override
  Stream<BonsoirDiscoveryEvent>? get eventStream => _controller.stream;
  @override
  Future<void> start() async {
    startCalls++;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    await _controller.close();
  }
}

class _FakeBonsoirBroadcast implements BonsoirBroadcast {
  @override
  final BonsoirService service;
  int startCalls = 0;
  int stopCalls = 0;

  _FakeBonsoirBroadcast(this.service);

  @override
  Future<void> get ready async {}
  @override
  bool get isReady => true;
  @override
  bool get isStopped => stopCalls > 0;
  @override
  Stream<BonsoirBroadcastEvent>? get eventStream => null;
  @override
  Future<void> start() async {
    startCalls++;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
  }
}
