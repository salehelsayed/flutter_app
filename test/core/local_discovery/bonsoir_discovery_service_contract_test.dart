// Contract test for BonsoirDiscoveryService against faked bonsoir objects
// (injected via the createBroadcast/createDiscovery factory seams).
//
// This pins the mDNS mapping the Move Account pairing depends on:
// peer-found → auto-resolve → LocalPeer(host/port/peerId), the
// discover-on-send resolvePeer contract, and stopAdvertising's behavior of
// clearing peers and completing pending resolves with null — the exact
// mechanics behind the "restartAdvertising nukes in-flight migration peer
// resolution" hazard. Real-network mDNS stays on the device checklist.

import 'dart:async';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter_app/core/local_discovery/bonsoir_discovery_service.dart';
import 'package:flutter_app/core/local_discovery/local_discovery_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BonsoirDiscoveryService contract', () {
    late List<_FakeBonsoirBroadcast> broadcasts;
    late List<_FakeBonsoirDiscovery> discoveries;
    late BonsoirDiscoveryService service;

    _FakeBonsoirBroadcast broadcast() => broadcasts.last;
    _FakeBonsoirDiscovery discovery() => discoveries.last;

    setUp(() {
      broadcasts = <_FakeBonsoirBroadcast>[];
      discoveries = <_FakeBonsoirDiscovery>[];
      service = BonsoirDiscoveryService(
        createBroadcast: (bonsoirService) {
          final fake = _FakeBonsoirBroadcast(bonsoirService);
          broadcasts.add(fake);
          return fake;
        },
        createDiscovery: (type) {
          final fake = _FakeBonsoirDiscovery(type);
          discoveries.add(fake);
          return fake;
        },
      );
    });

    tearDown(() async {
      // Cancels the 20s refresh Timer.periodic. (Do not call dispose():
      // its unawaited stopAdvertising races the controller close.)
      await service.stopAdvertising();
    });

    Future<void> flush() => Future<void>.delayed(Duration.zero);

    test('startAdvertising wires broadcast + discovery with the peer TXT record',
        () async {
      await service.startAdvertising('me-peer', 54321);

      expect(broadcasts, hasLength(1));
      expect(broadcast().service.port, 54321);
      expect(broadcast().service.attributes['peerId'], 'me-peer');
      expect(broadcast().service.type, '_mknoon._tcp');
      expect(broadcast().startCalls, 1);
      expect(discoveries, hasLength(1));
      expect(discovery().type, '_mknoon._tcp');
      expect(discovery().startCalls, 1);
    });

    test('found event auto-resolves but does not surface a peer yet', () async {
      await service.startAdvertising('me-peer', 54321);

      discovery().emit(
        BonsoirDiscoveryEvent(
          type: BonsoirDiscoveryEventType.discoveryServiceFound,
          service: _peerService('peer-a', 51234),
        ),
      );
      await flush();

      expect(discovery().resolver.resolved, hasLength(1));
      expect(discovery().resolver.resolved.single.attributes['peerId'], 'peer-a');
      expect(service.discoveredPeers, isEmpty);
    });

    test('resolved event maps to a LocalPeer and emits a snapshot', () async {
      await service.startAdvertising('me-peer', 54321);
      final snapshots = <Map<String, LocalPeer>>[];
      final sub = service.discoveredPeersStream.listen(snapshots.add);
      addTearDown(sub.cancel);

      discovery().emit(_resolvedEvent('peer-a', host: '192.168.0.9', port: 51234));
      await flush();

      final peer = service.discoveredPeers['peer-a'];
      expect(peer, isNotNull);
      expect(peer!.host, '192.168.0.9');
      expect(peer.port, 51234);
      expect(snapshots, isNotEmpty);
      expect(snapshots.last.containsKey('peer-a'), isTrue);
    });

    test('own peer and host-less resolutions are dropped', () async {
      await service.startAdvertising('me-peer', 54321);

      discovery().emit(_resolvedEvent('me-peer', host: '192.168.0.5', port: 1));
      discovery().emit(
        _resolvedEvent('peer-nohost', host: null, port: 51234),
      );
      await flush();

      expect(service.discoveredPeers, isEmpty);
    });

    test('resolvePeer completes when the awaited peer resolves', () async {
      await service.startAdvertising('me-peer', 54321);

      final pending = service.resolvePeer(
        'peer-b',
        timeout: const Duration(seconds: 5),
      );
      await flush();
      discovery().emit(_resolvedEvent('peer-b', host: '192.168.0.7', port: 50001));

      final peer = await pending;
      expect(peer, isNotNull);
      expect(peer!.host, '192.168.0.7');
    });

    test(
      'resolvePeer single-flights against an in-flight found resolve, then '
      'allows a fresh resolve once it completes (B1.2)',
      () async {
        await service.startAdvertising('me-peer', 54321);
        discovery().emit(
          BonsoirDiscoveryEvent(
            type: BonsoirDiscoveryEventType.discoveryServiceFound,
            service: _peerService('peer-c', 50002),
          ),
        );
        await flush();
        expect(discovery().resolver.resolved, hasLength(1));

        // B1.2: a resolve for peer-c is already in flight, so discover-on-send
        // must NOT issue a duplicate (each extra native resolve is a UAF window).
        final pending = service.resolvePeer(
          'peer-c',
          timeout: const Duration(seconds: 5),
        );
        await flush();
        expect(
          discovery().resolver.resolved,
          hasLength(1),
          reason: 'single-flight: no duplicate resolve while one is in flight',
        );

        // The in-flight resolve answering still wakes the awaiting send.
        discovery()
            .emit(_resolvedEvent('peer-c', host: '192.168.0.9', port: 50002));
        final peer = await pending;
        expect(peer, isNotNull);
        expect(peer!.host, '192.168.0.9');

        // Once it completed, a fresh found resolves again (flag cleared).
        discovery().emit(
          BonsoirDiscoveryEvent(
            type: BonsoirDiscoveryEventType.discoveryServiceFound,
            service: _peerService('peer-c', 50002),
          ),
        );
        await flush();
        expect(
          discovery().resolver.resolved,
          hasLength(2),
          reason: 'a fresh found after completion resolves again',
        );
      },
    );

    test('does not resolve our OWN advertised service (B1.1)', () async {
      await service.startAdvertising('me-peer', 54321);

      // A found event echoing our own peerId must NOT trigger a resolve.
      discovery().emit(
        BonsoirDiscoveryEvent(
          type: BonsoirDiscoveryEventType.discoveryServiceFound,
          service: _peerService('me-peer', 54321),
        ),
      );
      await flush();
      expect(
        discovery().resolver.resolved,
        isEmpty,
        reason: 'own advertised service must never be resolved',
      );

      // A foreign peer IS resolved.
      discovery().emit(
        BonsoirDiscoveryEvent(
          type: BonsoirDiscoveryEventType.discoveryServiceFound,
          service: _peerService('peer-x', 50005),
        ),
      );
      await flush();
      expect(discovery().resolver.resolved, hasLength(1));
    });

    test('resolvePeer is a no-op after stopAdvertising (B1.4)', () async {
      await service.startAdvertising('me-peer', 54321);
      discovery().emit(
        BonsoirDiscoveryEvent(
          type: BonsoirDiscoveryEventType.discoveryServiceFound,
          service: _peerService('peer-d', 50006),
        ),
      );
      await flush();
      final resolver = discovery().resolver;
      final countBefore = resolver.resolved.length;

      await service.stopAdvertising();
      final peer = await service.resolvePeer(
        'peer-d',
        timeout: const Duration(milliseconds: 50),
      );

      expect(peer, isNull);
      expect(
        resolver.resolved,
        hasLength(countBefore),
        reason: 'no resolve may be issued after teardown (B1.4)',
      );
    });

    test(
      'stopAdvertising clears peers and fails pending resolves to null',
      () async {
        await service.startAdvertising('me-peer', 54321);
        discovery().emit(
          _resolvedEvent('peer-a', host: '192.168.0.9', port: 51234),
        );
        await flush();
        expect(service.discoveredPeers, hasLength(1));

        final snapshots = <Map<String, LocalPeer>>[];
        final sub = service.discoveredPeersStream.listen(snapshots.add);
        addTearDown(sub.cancel);
        final pending = service.resolvePeer(
          'peer-never',
          timeout: const Duration(seconds: 30),
        );
        await flush();

        // This is the restartAdvertising hazard: an in-flight migration
        // resolve is completed with null the moment advertising restarts.
        await service.stopAdvertising();
        await flush();

        expect(await pending, isNull);
        expect(service.discoveredPeers, isEmpty);
        expect(snapshots.last, isEmpty);
        expect(broadcast().stopCalls, 1);
        expect(discovery().stopCalls, 1);

        // Events after stop are ignored (subscription cancelled).
        discovery().emit(
          _resolvedEvent('peer-late', host: '192.168.0.3', port: 1),
        );
        await flush();
        expect(service.discoveredPeers, isEmpty);
      },
    );

    test('a restart cycle mints fresh bonsoir objects and a fresh epoch',
        () async {
      await service.startAdvertising('me-peer', 54321);
      discovery().emit(_resolvedEvent('peer-a', host: '192.168.0.9', port: 51234));
      await flush();
      expect(service.discoveredPeers, hasLength(1));

      // Mirrors LocalP2PService.restartAdvertising (health-check path).
      await service.stopAdvertising();
      await service.startAdvertising('me-peer', 54321);

      expect(broadcasts, hasLength(2));
      expect(discoveries, hasLength(2));
      expect(
        service.discoveredPeers,
        isEmpty,
        reason: 'a restart begins a fresh discovery epoch',
      );

      // The new epoch's stream works.
      discoveries.last.emit(
        _resolvedEvent('peer-d', host: '192.168.0.4', port: 50004),
      );
      await flush();
      expect(service.discoveredPeers.keys, ['peer-d']);
    });

    // T12 (FDC-11): the advertisement carries the libp2p QUIC (+TCP) listen
    // ports in the TXT, distinct from the wsPort — FDC-S2's hard requirement
    // ("advertise the libp2p QUIC port, NOT wsPort").
    test('startAdvertising publishes libp2p quicPort in the TXT', () async {
      await service.startAdvertising(
        'me-peer',
        54321,
        quicPort: 45000,
        tcpPort: 45001,
      );

      final attrs = broadcast().service.attributes;
      expect(broadcast().service.port, 54321, reason: 'wsPort advert stays');
      expect(attrs['quicPort'], '45000');
      expect(attrs['tcpPort'], '45001');
      expect(attrs['peerId'], 'me-peer');
      // The QUIC port must be distinct from the wsPort (the whole point).
      expect(attrs['quicPort'], isNot('54321'));
    });

    // T13 (FDC-11): a resolved peer carries the libp2p QUIC multiaddr built from
    // the TXT quicPort — never from service.port (= wsPort), which would feed
    // the dial the wrong port (the FDC-S2 hang as a config bug).
    test('resolved peer carries libp2p QUIC multiaddr built from TXT', () async {
      await service.startAdvertising('me-peer', 54321);

      discovery().emit(
        _resolvedEvent(
          'peer-a',
          host: '192.168.0.9',
          port: 54321, // wsPort
          quicPort: 45000,
          tcpPort: 45001,
        ),
      );
      await flush();

      final peer = service.discoveredPeers['peer-a'];
      expect(peer, isNotNull);
      expect(peer!.libp2pAddresses, contains('/ip4/192.168.0.9/udp/45000/quic-v1'));
      expect(peer.libp2pAddresses, contains('/ip4/192.168.0.9/tcp/45001'));
      // NEVER the wsPort (54321) in any built multiaddr.
      expect(
        peer.libp2pAddresses.any((a) => a.contains('54321')),
        isFalse,
        reason: 'must build from quicPort/tcpPort, never the wsPort',
      );
    });
  });
}

BonsoirService _peerService(String peerId, int port) {
  return BonsoirService(
    name: 'mknoon',
    type: '_mknoon._tcp',
    port: port,
    attributes: {'peerId': peerId},
  );
}

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
    if (!_controller.isClosed) {
      _controller.add(event);
    }
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
