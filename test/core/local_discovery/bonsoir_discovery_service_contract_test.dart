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
import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride, TargetPlatform;
import 'package:flutter_app/core/local_discovery/bonsoir_discovery_service.dart';
import 'package:flutter_app/core/local_discovery/local_discovery_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
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

    // FDC-11 device fix: the advertised mDNS *instance name* must be unique per
    // device. A fixed name ('mknoon') collides whenever 2+ devices share a LAN;
    // mDNS renames the loser to 'mknoon (2)' (space + parens), which Android
    // NsdManager cannot resolve → the peer is browsed but never resolves
    // (PEER_LOST without PEER_FOUND), killing LAN-direct that way. The browse
    // TYPE and the TXT peerId are unchanged, so it stays transparent to peers.
    test('advertised instance name is unique per device (not the bare name)',
        () async {
      const peerId = '12D3KooWFFxjyY1qsYFQYD8SUD26XSZarQASXAamWf31ZieUggcw';
      await service.startAdvertising(peerId, 54321);

      final name = broadcasts.single.service.name;
      expect(name, isNot('mknoon'),
          reason: 'a fixed name collides on a shared LAN → mDNS renames it to '
              'a space/paren name NsdManager cannot resolve');
      expect(name, startsWith('mknoon-'));
      expect(name, endsWith(peerId.substring(peerId.length - 12)));
      // Identity still travels in the TXT; the browse type is unchanged.
      expect(broadcasts.single.service.attributes['peerId'], peerId);
      expect(broadcasts.single.service.type, '_mknoon._tcp');
    });

    test('distinct peers advertise distinct instance names (no collision)',
        () async {
      await service.startAdvertising('peerAAAAAAAAAAAA', 1);
      final nameA = broadcasts.last.service.name;
      await service.stopAdvertising();
      await service.startAdvertising('peerBBBBBBBBBBBB', 2);
      final nameB = broadcasts.last.service.name;
      expect(nameA, isNot(nameB));
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

    // FDC-11 device fix: iOS bonsoir resolves a peer to its `.local` HOSTNAME
    // (not a numeric IP, as Android's NsdManager does). A hostname placed in an
    // /ip4 multiaddr fails to parse in libp2p, so the LAN dial never happens —
    // build /dns4 (trailing dot stripped) and let libp2p resolve it at dial time.
    test('resolved peer with a .local hostname builds a /dns4 multiaddr',
        () async {
      await service.startAdvertising('me-peer', 54321);

      discovery().emit(
        _resolvedEvent(
          'peer-h',
          host: 'Android_9DNYWLJG.local.',
          port: 54321,
          quicPort: 45000,
          tcpPort: 45001,
        ),
      );
      await flush();

      final peer = service.discoveredPeers['peer-h'];
      expect(peer, isNotNull);
      expect(peer!.libp2pAddresses,
          contains('/dns4/Android_9DNYWLJG.local/udp/45000/quic-v1'));
      expect(peer.libp2pAddresses,
          contains('/dns4/Android_9DNYWLJG.local/tcp/45001'));
      expect(
        peer.libp2pAddresses.any((a) => a.startsWith('/ip4/')),
        isFalse,
        reason: 'a hostname must never be placed in an /ip4 multiaddr',
      );
    });
  });

  // iOS Local Network watchdog mitigation: the native bonsoir broadcast start
  // does a synchronous DNS-SD read on the main thread; when Local Network
  // permission is denied/pending it blocks past the 10s scene-update watchdog
  // → SIGKILL (0x8BADF00D). The gate skips the native (re)start once advertising
  // ran the probe window with zero peers (restartAdvertising is the crash
  // vector), re-probing after a backoff and clearing on a real peer resolve.
  group('BonsoirDiscoveryService Local Network watchdog gate', () {
    late List<_FakeBonsoirBroadcast> broadcasts;
    late List<_FakeBonsoirDiscovery> discoveries;
    late BonsoirDiscoveryService service;

    BonsoirDiscoveryService build({
      Duration probe = const Duration(milliseconds: 50),
      Duration backoff = const Duration(seconds: 10),
    }) {
      return BonsoirDiscoveryService(
        suspectedDenialProbe: probe,
        suspectedDenialBackoff: backoff,
        createBroadcast: (s) {
          final fake = _FakeBonsoirBroadcast(s);
          broadcasts.add(fake);
          return fake;
        },
        createDiscovery: (type) {
          final fake = _FakeBonsoirDiscovery(type);
          discoveries.add(fake);
          return fake;
        },
      );
    }

    setUp(() {
      broadcasts = <_FakeBonsoirBroadcast>[];
      discoveries = <_FakeBonsoirDiscovery>[];
      // 178: the suspected-denied latch is now iOS-only. This group exercises
      // the iOS watchdog gate, so pin the platform to iOS (the default host
      // test platform is android, on which the gate never latches — TC-78-01).
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    });

    tearDown(() async {
      await service.stopAdvertising();
      debugSetFlowEventSink(null);
      debugDefaultTargetPlatformOverride = null;
    });

    // Mirrors LocalP2PService.restartAdvertising (resume / address-update).
    Future<void> restart() async {
      await service.stopAdvertising();
      await service.startAdvertising('me-peer', 54321);
    }

    test(
      'zero peers after the probe latches the gate; the restart broadcast start is SKIPPED',
      () async {
        service = build(backoff: const Duration(seconds: 10));
        await service.startAdvertising('me-peer', 54321);
        expect(broadcasts, hasLength(1));
        expect(broadcasts.single.startCalls, 1);

        // Advertising stayed active with zero discovered peers across the probe.
        await Future<void>.delayed(const Duration(milliseconds: 120));
        expect(service.debugSuspectedLocalNetworkUnavailable, isTrue);

        final events = <Map<String, dynamic>>[];
        debugSetFlowEventSink(events.add);

        // The restart's native bonsoir BROADCAST start MUST be skipped (the
        // crash vector). 178: the browse still runs — only the broadcast gates.
        await restart();
        expect(
          broadcasts,
          hasLength(1),
          reason: 'no new native broadcast created → start() never called',
        );
        expect(
          events.where(
            (e) => e['event'] == 'LOCAL_MDNS_ADVERTISE_SKIPPED_SUSPECTED_DENIED',
          ),
          hasLength(1),
        );
      },
    );

    test('a resolved peer before the probe keeps the gate OPEN (restart starts)',
        () async {
      service = build();
      await service.startAdvertising('me-peer', 54321);
      // A real peer resolves → Local Network is working.
      discoveries.single.emit(
        _resolvedEvent('peer-x', host: '192.168.0.5', port: 1),
      );

      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(service.debugSuspectedLocalNetworkUnavailable, isFalse);

      await restart();
      expect(broadcasts, hasLength(2),
          reason: 'gate open → the restart starts a fresh broadcast');
    });

    test('a resolved peer AFTER the gate latches clears it (restart starts)',
        () async {
      service = build(backoff: const Duration(seconds: 10));
      await service.startAdvertising('me-peer', 54321);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(service.debugSuspectedLocalNetworkUnavailable, isTrue);

      // A peer shows up after the latch → Local Network is provably working.
      discoveries.single.emit(
        _resolvedEvent('peer-y', host: '192.168.0.6', port: 2),
      );
      // The discovery event is delivered on a microtask — let it be handled.
      await Future<void>.delayed(Duration.zero);
      expect(service.debugSuspectedLocalNetworkUnavailable, isFalse);

      await restart();
      expect(broadcasts, hasLength(2));
    });

    test('the gate re-opens after the backoff lapses (single re-probe)',
        () async {
      service = build(
        probe: const Duration(milliseconds: 50),
        backoff: const Duration(milliseconds: 120),
      );
      await service.startAdvertising('me-peer', 54321);
      await Future<void>.delayed(const Duration(milliseconds: 90));
      expect(service.debugSuspectedLocalNetworkUnavailable, isTrue);

      // After the backoff deadline passes, the gate re-opens on its own.
      await Future<void>.delayed(const Duration(milliseconds: 160));
      expect(service.debugSuspectedLocalNetworkUnavailable, isFalse);

      await restart();
      expect(broadcasts, hasLength(2),
          reason: 'backoff lapsed → the restart re-probes Local Network');
    });
  });

  // 178: the pure-Dart "suspected-Local-Network-denied" gate over-latched and
  // self-reinforced — it skipped the WHOLE startAdvertising (killing the
  // browse), and the only un-latch path needs the browse, so a latch was
  // terminal until the 5-min backoff. Two coupled fixes:
  //   (1) platform-gate the latch to iOS — Android has no Local-Network
  //       main-thread watchdog (the 0x8BADF00D class is iOS-only), and gating
  //       the broadcast on Android would break the working iPhone→Pixel
  //       direction (which needs the Pixel's advert).
  //   (2) on iOS, gate ONLY the broadcast; ALWAYS run the browse (it is
  //       off-main-safe post-175), so a resolved peer can self-clear the latch.
  group('BonsoirDiscoveryService suspected-denied gate (178 over-latch fix)', () {
    late List<_FakeBonsoirBroadcast> broadcasts;
    late List<_FakeBonsoirDiscovery> discoveries;
    late BonsoirDiscoveryService service;

    BonsoirDiscoveryService build({
      Duration probe = const Duration(milliseconds: 50),
      Duration backoff = const Duration(seconds: 10),
    }) {
      return BonsoirDiscoveryService(
        suspectedDenialProbe: probe,
        suspectedDenialBackoff: backoff,
        createBroadcast: (s) {
          final fake = _FakeBonsoirBroadcast(s);
          broadcasts.add(fake);
          return fake;
        },
        createDiscovery: (type) {
          final fake = _FakeBonsoirDiscovery(type);
          discoveries.add(fake);
          return fake;
        },
      );
    }

    setUp(() {
      broadcasts = <_FakeBonsoirBroadcast>[];
      discoveries = <_FakeBonsoirDiscovery>[];
    });

    tearDown(() async {
      await service.stopAdvertising();
      debugSetFlowEventSink(null);
      debugDefaultTargetPlatformOverride = null;
    });

    // TC-78-01 (INV-1): Android must NEVER latch. The probe window lapses with
    // zero peers — on HEAD the platform-blind `_armSuspectedDenialProbe` latches
    // regardless of platform; the fix gates the latch to iOS.
    test('Android never latches the suspected-denied gate', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final events = <Map<String, dynamic>>[];
      debugSetFlowEventSink(events.add);

      service = build(probe: const Duration(milliseconds: 50));
      await service.startAdvertising('me-peer', 54321);

      // Advertising stays active with zero discovered peers across the probe.
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(service.debugSuspectedLocalNetworkUnavailable, isFalse,
          reason: 'Android has no Local-Network watchdog → never latch');
      expect(
        events.where(
          (e) => e['event'] == 'LOCAL_MDNS_SUSPECTED_DENIED_GATE_LATCHED',
        ),
        isEmpty,
        reason: 'no LATCHED event may fire on Android',
      );

      // The browse stays up: a peer can still resolve on Android.
      discoveries.single.emit(
        _resolvedEvent('peer-x', host: '192.168.0.5', port: 1),
      );
      await Future<void>.delayed(Duration.zero);
      expect(service.discoveredPeers, hasLength(1),
          reason: 'browse never gets gated on Android');
    });

    // TC-78-02 (INV-2): on iOS, a latched gate skips the BROADCAST but the
    // browse MUST keep running. Discriminator: in the same restart,
    // DISCOVERY_START present AND ADVERTISE_START absent (proves "browse runs,
    // broadcast gated", not "both run" nor "both skipped").
    test('iOS suspected-denied skips the broadcast but KEEPS the browse running',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      service = build(backoff: const Duration(seconds: 10));
      await service.startAdvertising('me-peer', 54321);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(service.debugSuspectedLocalNetworkUnavailable, isTrue);

      final events = <Map<String, dynamic>>[];
      debugSetFlowEventSink(events.add);

      // restartAdvertising (resume / address-update): broadcast gated, browse on.
      await service.stopAdvertising();
      await service.startAdvertising('me-peer', 54321);

      final names = events.map((e) => e['event']).toList();
      expect(names, contains('LOCAL_MDNS_DISCOVERY_START'),
          reason: 'the browse ALWAYS runs, even while the broadcast is gated');
      expect(names, isNot(contains('LOCAL_MDNS_ADVERTISE_START')),
          reason: 'the broadcast (re)start is gated on a suspected denial');
      expect(names, contains('LOCAL_MDNS_ADVERTISE_SKIPPED_SUSPECTED_DENIED'),
          reason: 'the gated-broadcast path is observable as a distinct event');
      expect(broadcasts, hasLength(1),
          reason: 'no new native broadcast object while the broadcast is gated');
      expect(discoveries, hasLength(2),
          reason: 'a fresh discovery object — the browse restarted');
    });

    // TC-78-03 (INV-2): the latch SELF-CLEARS on iOS because the browse keeps
    // running — a peer resolves through the still-up browse and clears
    // `_suspectedDeniedUntil`, so the next start re-advertises.
    test('iOS latch self-clears when a peer resolves via the still-running browse',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      service = build(backoff: const Duration(seconds: 10));
      await service.startAdvertising('me-peer', 54321);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(service.debugSuspectedLocalNetworkUnavailable, isTrue);

      // restart: broadcast gated, but the browse runs (a NEW discovery object).
      await service.stopAdvertising();
      await service.startAdvertising('me-peer', 54321);

      // A peer resolves through the still-running browse → Local Network proven.
      discoveries.last.emit(
        _resolvedEvent('peer-y', host: '192.168.0.6', port: 2),
      );
      await Future<void>.delayed(Duration.zero);
      expect(service.debugSuspectedLocalNetworkUnavailable, isFalse,
          reason: 'a resolved peer via the live browse clears the latch');

      // The next start re-advertises (broadcast runs again).
      await service.stopAdvertising();
      await service.startAdvertising('me-peer', 54321);
      expect(broadcasts, hasLength(2),
          reason: 'latch cleared → the broadcast is no longer skipped');
    });

    // TC-78-04 (INV-3, watchdog protection — PRESERVE): on iOS, while latched,
    // the broadcast (re)start MUST still be skipped — this is the 175/0x8BADF00D
    // main-thread-DNS-SD vector protection. Mutation: remove the broadcast gate
    // entirely → this goes red (watchdog vector reopened).
    test('iOS still gates the broadcast on suspected denial (watchdog protection)',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      service = build(backoff: const Duration(seconds: 10));
      await service.startAdvertising('me-peer', 54321);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(service.debugSuspectedLocalNetworkUnavailable, isTrue);

      final events = <Map<String, dynamic>>[];
      debugSetFlowEventSink(events.add);

      await service.stopAdvertising();
      await service.startAdvertising('me-peer', 54321);

      final names = events.map((e) => e['event']).toList();
      expect(names, isNot(contains('LOCAL_MDNS_ADVERTISE_START')),
          reason: 'no native broadcast (re)start while latched (watchdog vector '
              'stays closed)');
      expect(names, contains('LOCAL_MDNS_ADVERTISE_SKIPPED_SUSPECTED_DENIED'));
      expect(broadcasts, hasLength(1),
          reason: 'no new native broadcast object created while latched');
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
