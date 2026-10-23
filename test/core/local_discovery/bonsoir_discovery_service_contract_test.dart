// Contract test for BonsoirDiscoveryService against faked bonsoir objects
// (injected via the createBroadcast/createDiscovery factory seams).
//
// This pins the mDNS mapping the Move Account pairing depends on:
// peer-found → auto-resolve → LocalPeer(host/port/peerId), the
// discover-on-send resolvePeer contract, healthy advertisement refresh without
// browser/cache loss, and real stop/error replacement clearing the native epoch.
// Real-network mDNS stays on the device checklist.

import 'dart:async';
import 'dart:convert';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride, TargetPlatform;
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_app/app/lifecycle/handle_app_resumed.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/local_discovery/bonsoir_discovery_service.dart';
import 'package:flutter_app/core/local_discovery/local_discovery_service.dart';
import 'package:flutter_app/core/local_discovery/local_p2p_service.dart';
import 'package:flutter_app/core/local_discovery/local_ws_server.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../shared/fakes/in_memory_inbox_staging_repository.dart';

void main() {
  group('BonsoirDiscoveryService contract', () {
    late List<_FakeBonsoirBroadcast> broadcasts;
    late List<_FakeBonsoirDiscovery> discoveries;
    late BonsoirDiscoveryService service;
    Object? discoveryStartError;
    Future<void>? broadcastStartGate;

    _FakeBonsoirBroadcast broadcast() => broadcasts.last;
    _FakeBonsoirDiscovery discovery() => discoveries.last;

    setUp(() {
      broadcasts = <_FakeBonsoirBroadcast>[];
      discoveries = <_FakeBonsoirDiscovery>[];
      discoveryStartError = null;
      broadcastStartGate = null;
      service = BonsoirDiscoveryService(
        createBroadcast: (bonsoirService) {
          final fake = _FakeBonsoirBroadcast(bonsoirService)
            ..startGate = broadcastStartGate;
          broadcasts.add(fake);
          return fake;
        },
        createDiscovery: (type) {
          final fake = _FakeBonsoirDiscovery(type)
            ..startError = discoveryStartError;
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

    Future<P2PServiceImpl> healthService(
      _DiscoveryHealthBridge bridge,
      LocalP2PService local,
    ) async {
      final p2p = P2PServiceImpl(
        bridge: bridge,
        localP2PService: local,
        inboxStagingRepository: InMemoryInboxStagingRepository(),
        isAppForeground: () => true,
      );
      addTearDown(() async {
        await local.stop();
        p2p.dispose();
        await flush();
      });
      expect(
        await p2p.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer'),
        isTrue,
      );
      await local.start('self-peer');
      return p2p;
    }

    test(
      'relay_state_push health check preserves browser peers and resolver handles',
      () async {
        final ws = LocalWsServer();
        addTearDown(ws.stop);
        final local = _ExternallyOwnedLocalP2PService(
          discovery: service,
          wsServer: ws,
        );
        final bridge = _DiscoveryHealthBridge();
        await healthService(bridge, local);
        final browser = discovery();
        browser.emit(
          BonsoirDiscoveryEvent(
            type: BonsoirDiscoveryEventType.discoveryServiceFound,
            service: _peerService('peer-a', 51234),
          ),
        );
        await flush();
        browser.emit(
          _resolvedEvent('peer-a', host: '192.168.0.7', port: 51234),
        );
        await flush();
        final waiting = service.resolvePeer(
          'pending-health',
          timeout: const Duration(seconds: 12),
        );
        var completed = false;
        unawaited(waiting.then((_) => completed = true));
        final events = <Map<String, dynamic>>[];
        final refreshed = Completer<void>();
        debugSetFlowEventSink((event) {
          events.add(event);
          if (event['event'] == 'LOCAL_P2P_SERVICE_RESTART_ADVERTISING' &&
              !refreshed.isCompleted) {
            refreshed.complete();
          }
        });
        addTearDown(() => debugSetFlowEventSink(null));

        bridge.relayState = 'degraded';
        bridge.onRelayStateChanged!({
          'relayState': 'degraded',
          'healthyRelayCount': 0,
          'reason': 'fixture-degradation',
        });
        await refreshed.future.timeout(const Duration(seconds: 5));
        await flush();

        expect(
          events
              .where((e) => e['event'] == 'RELAY_RECOVERY_START')
              .any(
                (e) =>
                    (e['details'] as Map)['recoverySource'] ==
                    'relay_state_push',
              ),
          isTrue,
        );
        expect(discoveries, hasLength(1));
        expect(browser.stopCalls, 0);
        expect(service.getLocalPeer('peer-a'), isNotNull);
        expect(completed, isFalse);
        service.debugSeedPeer(
          LocalPeer(
            peerId: 'peer-a',
            host: '192.168.0.7',
            port: 51234,
            discoveredAt: DateTime.now().toUtc().subtract(
              const Duration(seconds: 31),
            ),
          ),
        );
        final pending = service.resolvePeer(
          'peer-a',
          timeout: const Duration(seconds: 12),
        );
        await flush();
        expect(browser.resolver.resolved, hasLength(2));
        browser.emit(
          _resolvedEvent('peer-a', host: '192.168.0.8', port: 51235),
        );
        browser.emit(
          _resolvedEvent('pending-health', host: '192.168.0.9', port: 51236),
        );
        expect((await pending)!.host, '192.168.0.8');
        expect((await waiting)!.host, '192.168.0.9');
      },
    );

    test(
      'app lifecycle health check replaces browser without a native error',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final ws = LocalWsServer();
        addTearDown(ws.stop);
        final local = _ExternallyOwnedLocalP2PService(
          discovery: service,
          wsServer: ws,
        );
        final bridge = _DiscoveryHealthBridge();
        final p2p = await healthService(bridge, local);
        final browser = discovery();
        browser.emit(
          _resolvedEvent('peer-a', host: '192.168.0.7', port: 51234),
        );
        await flush();
        final waiting = service.resolvePeer(
          'pending-resume',
          timeout: const Duration(seconds: 12),
        );

        expect(await handleAppResumed(bridge: bridge, p2pService: p2p), isTrue);

        expect(browser.stopCalls, 1);
        expect(discoveries, hasLength(2));
        expect(service.discoveredPeers, isEmpty);
        expect(await waiting, isNull);
        await p2p.performImmediateHealthCheck();
        expect(
          discoveries,
          hasLength(2),
          reason:
              'a later generic health check must not reuse consumed resume intent',
        );
      },
    );

    test(
      'lifecycle resume escalates a coalesced relay health refresh',
      () async {
        final ws = LocalWsServer();
        addTearDown(ws.stop);
        final local = _ExternallyOwnedLocalP2PService(
          discovery: service,
          wsServer: ws,
        );
        final bridge = _DiscoveryHealthBridge();
        final p2p = await healthService(bridge, local);
        final browser = discovery();
        final gate = Completer<void>();
        broadcastStartGate = gate.future;
        bridge.relayState = 'degraded';
        bridge.onRelayStateChanged!({
          'relayState': 'degraded',
          'healthyRelayCount': 0,
        });
        await flush();
        expect(broadcasts, hasLength(2));
        expect(broadcasts.last.startCalls, 1);
        expect(browser.stopCalls, 0);

        p2p.markResumeStarted();
        var completed = false;
        final joined = p2p.performImmediateHealthCheck().then(
          (_) => completed = true,
        );
        await flush();
        expect(completed, isFalse);
        gate.complete();
        await joined;

        expect(browser.stopCalls, 1);
        expect(discoveries, hasLength(2));
        expect(broadcasts, hasLength(3));
      },
    );

    test(
      'startAdvertising wires broadcast + discovery with the peer TXT record',
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
      },
    );

    // FDC-11 device fix: the advertised mDNS *instance name* must be unique per
    // device. A fixed name ('mknoon') collides whenever 2+ devices share a LAN;
    // mDNS renames the loser to 'mknoon (2)' (space + parens), which Android
    // NsdManager cannot resolve → the peer is browsed but never resolves
    // (PEER_LOST without PEER_FOUND), killing LAN-direct that way. The browse
    // TYPE and the TXT peerId are unchanged, so it stays transparent to peers.
    test(
      'advertised instance name is unique per device (not the bare name)',
      () async {
        const peerId = '12D3KooWFFxjyY1qsYFQYD8SUD26XSZarQASXAamWf31ZieUggcw';
        await service.startAdvertising(peerId, 54321);

        final name = broadcasts.single.service.name;
        expect(
          name,
          isNot('mknoon'),
          reason:
              'a fixed name collides on a shared LAN → mDNS renames it to '
              'a space/paren name NsdManager cannot resolve',
        );
        expect(name, startsWith('mknoon-'));
        expect(name, endsWith(peerId.substring(peerId.length - 12)));
        // Identity still travels in the TXT; the browse type is unchanged.
        expect(broadcasts.single.service.attributes['peerId'], peerId);
        expect(broadcasts.single.service.type, '_mknoon._tcp');
      },
    );

    test(
      'distinct peers advertise distinct instance names (no collision)',
      () async {
        await service.startAdvertising('peerAAAAAAAAAAAA', 1);
        final nameA = broadcasts.last.service.name;
        await service.stopAdvertising();
        await service.startAdvertising('peerBBBBBBBBBBBB', 2);
        final nameB = broadcasts.last.service.name;
        expect(nameA, isNot(nameB));
      },
    );

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
      expect(
        discovery().resolver.resolved.single.attributes['peerId'],
        'peer-a',
      );
      expect(service.discoveredPeers, isEmpty);
    });

    test(
      'native discovery errors are contained before normal resume restart',
      () async {
        final events = <Map<String, dynamic>>[];
        debugSetFlowEventSink(events.add);
        addTearDown(() => debugSetFlowEventSink(null));
        final ws = LocalWsServer();
        addTearDown(ws.stop);
        final local = LocalP2PService(discovery: service, wsServer: ws);
        await local.start('me-peer');
        final oldBrowser = discovery();
        oldBrowser.emit(
          BonsoirDiscoveryEvent(
            type: BonsoirDiscoveryEventType.discoveryServiceFound,
            service: _peerService('peer-a', 51234),
          ),
        );
        await flush();
        oldBrowser.emit(
          _resolvedEvent('peer-a', host: '192.168.0.7', port: 51234),
        );
        await flush();
        final interrupted = service.resolvePeer(
          'pending-before-error',
          timeout: const Duration(seconds: 12),
        );

        discovery().emitError(
          PlatformException(
            code: 'discoveryError',
            message: 'private-native-message',
            details: -65569,
          ),
        );
        await flush();

        final failures = events.where(
          (event) => event['event'] == 'LOCAL_MDNS_DISCOVERY_ERROR',
        );
        expect(failures, hasLength(1));
        expect(failures.single['details'], {
          'reason': 'nativeDiscoveryFailure',
          'nativeCode': -65569,
        });
        expect(events.toString(), isNot(contains('private-native-message')));
        expect(broadcasts, hasLength(1));

        // Normal resume replaces a genuinely defunct native browser, rather
        // than retaining handles that belonged to its destroyed native epoch.
        await local.restartAdvertising();
        expect(oldBrowser.stopCalls, 1);
        expect(await interrupted, isNull);
        expect(service.discoveredPeers, isEmpty);
        final pending = service.resolvePeer(
          'peer-a',
          timeout: const Duration(seconds: 12),
        );
        await flush();
        expect(discovery().resolver.resolved, isEmpty);
        discovery().emit(
          BonsoirDiscoveryEvent(
            type: BonsoirDiscoveryEventType.discoveryServiceFound,
            service: _peerService('peer-a', 51234),
          ),
        );
        await flush();
        expect(discovery().resolver.resolved, hasLength(1));
        discovery().emit(
          _resolvedEvent('peer-a', host: '192.168.0.9', port: 51234),
        );
        await flush();
        expect(discoveries, hasLength(2));
        expect((await pending)!.host, '192.168.0.9');
        expect(service.discoveredPeers, contains('peer-a'));
      },
    );

    test(
      'failed native browser start retries with a new discovery epoch',
      () async {
        discoveryStartError = StateError('fixture native start failure');
        await expectLater(
          service.startAdvertising('me-peer', 54321),
          throwsStateError,
        );
        expect(discoveries, hasLength(1));
        discoveryStartError = null;

        await service.startAdvertising('me-peer', 54321);

        expect(discoveries, hasLength(2));
        expect(discoveries.first.stopCalls, 1);
        expect(discoveries.last.startCalls, 1);
        discovery().emit(
          _resolvedEvent('peer-a', host: '192.168.0.9', port: 51234),
        );
        await flush();
        expect(service.getLocalPeer('peer-a'), isNotNull);
      },
    );

    test('resolved event maps to a LocalPeer and emits a snapshot', () async {
      await service.startAdvertising('me-peer', 54321);
      final snapshots = <Map<String, LocalPeer>>[];
      final sub = service.discoveredPeersStream.listen(snapshots.add);
      addTearDown(sub.cancel);

      discovery().emit(
        _resolvedEvent('peer-a', host: '192.168.0.9', port: 51234),
      );
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
      discovery().emit(_resolvedEvent('peer-nohost', host: null, port: 51234));
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
      discovery().emit(
        _resolvedEvent('peer-b', host: '192.168.0.7', port: 50001),
      );

      final peer = await pending;
      expect(peer, isNotNull);
      expect(peer!.host, '192.168.0.7');
    });

    test(
      'expired migration endpoint actively re-resolves its retained handle',
      () async {
        const peerId = 'account-migration-0123456789abcdef0123456789abcdef';
        await service.startAdvertising('me-peer', 54321);
        discovery().emit(
          BonsoirDiscoveryEvent(
            type: BonsoirDiscoveryEventType.discoveryServiceFound,
            service: _peerService(peerId, 51234),
          ),
        );
        await flush();
        discovery().emit(
          _resolvedEvent(peerId, host: '192.168.0.7', port: 51234),
        );
        await flush();
        expect(discovery().resolver.resolved, hasLength(1));
        service.debugSeedPeer(
          LocalPeer(
            peerId: peerId,
            host: '192.168.0.7',
            port: 51234,
            discoveredAt: DateTime.now().toUtc().subtract(
              const Duration(seconds: 31),
            ),
          ),
        );

        final pending = service.resolvePeer(
          peerId,
          timeout: const Duration(seconds: 12),
        );
        var completed = false;
        unawaited(pending.then((_) => completed = true));
        await flush();
        expect(service.getLocalPeer(peerId), isNull);
        expect(completed, isFalse);
        expect(discovery().resolver.resolved, hasLength(2));
        final joined = service.resolvePeer(
          peerId,
          timeout: const Duration(seconds: 12),
        );
        await flush();
        expect(discovery().resolver.resolved, hasLength(2));

        discovery().emit(
          _resolvedEvent(peerId, host: '192.168.0.8', port: 51235),
        );
        for (final peer in await Future.wait([pending, joined])) {
          expect(peer, isNotNull);
          expect(peer!.host, '192.168.0.8');
          expect(peer.port, 51235);
          expect(peer.libp2pAddresses, isEmpty);
        }
      },
    );

    test(
      'early migration resolve accepts an HTTP peer without libp2p ports',
      () async {
        const peerId = 'account-migration-0123456789abcdef0123456789abcdef';
        await service.startAdvertising('me-peer', 54321);
        final pending = service.resolvePeer(
          peerId,
          timeout: const Duration(seconds: 12),
        );
        await flush();
        discovery().emit(
          BonsoirDiscoveryEvent(
            type: BonsoirDiscoveryEventType.discoveryServiceFound,
            service: _peerService(peerId, 51234),
          ),
        );
        await flush();
        expect(discovery().resolver.resolved, hasLength(1));
        discovery().emit(
          _resolvedEvent(peerId, host: '192.168.0.7', port: 51234),
        );

        final peer = await pending;
        expect(peer, isNotNull);
        expect(peer!.host, '192.168.0.7');
        expect(peer.port, 51234);
        expect(peer.libp2pAddresses, isEmpty);
      },
    );

    test('TXT refresh preserves browser cache and pending resolves', () async {
      final ws = LocalWsServer();
      addTearDown(ws.stop);
      final local = LocalP2PService(discovery: service, wsServer: ws);
      await local.start('me-peer');
      final browser = discovery();
      browser.emit(
        _resolvedEvent('cached-peer', host: '192.168.0.7', port: 51234),
      );
      browser.emit(
        BonsoirDiscoveryEvent(
          type: BonsoirDiscoveryEventType.discoveryServiceFound,
          service: _peerService('pending-peer', 51235),
        ),
      );
      await flush();
      final pending = service.resolvePeer(
        'pending-peer',
        timeout: const Duration(seconds: 12),
      );
      var completed = false;
      unawaited(pending.then((_) => completed = true));

      await local.updateLibp2pPorts(quicPort: 45000, tcpPort: 45001);
      expect(discoveries, hasLength(1));
      expect(browser.stopCalls, 0);
      expect(service.getLocalPeer('cached-peer'), isNotNull);
      expect(completed, isFalse);
      expect(broadcasts, hasLength(2));
      expect(broadcasts.first.stopCalls, 1);
      expect(broadcast().service.attributes['quicPort'], '45000');
      expect(broadcast().service.attributes['tcpPort'], '45001');

      await local.updateLibp2pPorts(quicPort: 45002, tcpPort: 45003);
      expect(discoveries, hasLength(1));
      expect(browser.stopCalls, 0);
      expect(service.getLocalPeer('cached-peer'), isNotNull);
      expect(completed, isFalse);
      expect(browser.resolver.resolved, hasLength(1));
      expect(broadcasts, hasLength(3));
      expect(broadcasts[1].stopCalls, 1);
      browser.emit(
        _resolvedEvent('pending-peer', host: '192.168.0.8', port: 51235),
      );
      expect((await pending)!.host, '192.168.0.8');
    });

    test(
      'iOS resume replaces the browser without a prior error event',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final ws = LocalWsServer();
        addTearDown(ws.stop);
        final local = LocalP2PService(discovery: service, wsServer: ws);
        await local.start('me-peer');
        final oldBrowser = discovery();
        oldBrowser.emit(
          BonsoirDiscoveryEvent(
            type: BonsoirDiscoveryEventType.discoveryServiceFound,
            service: _peerService('peer-a', 51234),
          ),
        );
        await flush();
        oldBrowser.emit(
          _resolvedEvent('peer-a', host: '192.168.0.7', port: 51234),
        );
        await flush();
        final interrupted = service.resolvePeer(
          'pending-before-resume',
          timeout: const Duration(seconds: 12),
        );

        // No stream error is delivered for this suspended browser.
        local.markAppResumed();
        await local.restartAdvertising();

        expect(oldBrowser.stopCalls, 1);
        expect(discoveries, hasLength(2));
        expect(await interrupted, isNull);
        expect(service.discoveredPeers, isEmpty);
        final pending = service.resolvePeer(
          'peer-a',
          timeout: const Duration(seconds: 12),
        );
        await flush();
        expect(discovery().resolver.resolved, isEmpty);
        discovery().emit(
          BonsoirDiscoveryEvent(
            type: BonsoirDiscoveryEventType.discoveryServiceFound,
            service: _peerService('peer-a', 51235),
          ),
        );
        await flush();
        expect(discovery().resolver.resolved, hasLength(1));
        discovery().emit(
          _resolvedEvent('peer-a', host: '192.168.0.8', port: 51235),
        );
        expect((await pending)!.host, '192.168.0.8');
      },
    );

    test(
      'resume joining an active TXT refresh still replaces the browser',
      () async {
        final ws = LocalWsServer();
        addTearDown(ws.stop);
        final local = LocalP2PService(discovery: service, wsServer: ws);
        await local.start('me-peer');
        final oldBrowser = discovery();
        final gate = Completer<void>();
        broadcastStartGate = gate.future;
        final ports = local.updateLibp2pPorts(quicPort: 45000, tcpPort: 45001);
        await flush();
        expect(broadcasts, hasLength(2));
        expect(broadcasts.last.startCalls, 1);
        local.markAppResumed();
        final resume = local.restartAdvertising();
        await flush();
        gate.complete();
        await Future.wait([ports, resume]);

        expect(oldBrowser.stopCalls, 1);
        expect(discoveries, hasLength(2));
        expect(broadcasts, hasLength(3));
        expect(broadcast().service.attributes['quicPort'], '45000');
      },
    );

    test('resolvePeer single-flights against an in-flight found resolve, then '
        'allows a fresh resolve once it completes (B1.2)', () async {
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
      discovery().emit(
        _resolvedEvent('peer-c', host: '192.168.0.9', port: 50002),
      );
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
    });

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

    test(
      'a restart cycle mints fresh bonsoir objects and a fresh epoch',
      () async {
        await service.startAdvertising('me-peer', 54321);
        discovery().emit(
          _resolvedEvent('peer-a', host: '192.168.0.9', port: 51234),
        );
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
      },
    );

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
    test(
      'resolved peer carries libp2p QUIC multiaddr built from TXT',
      () async {
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
        expect(
          peer!.libp2pAddresses,
          contains('/ip4/192.168.0.9/udp/45000/quic-v1'),
        );
        expect(peer.libp2pAddresses, contains('/ip4/192.168.0.9/tcp/45001'));
        // NEVER the wsPort (54321) in any built multiaddr.
        expect(
          peer.libp2pAddresses.any((a) => a.contains('54321')),
          isFalse,
          reason: 'must build from quicPort/tcpPort, never the wsPort',
        );
      },
    );

    // FDC-11 device fix: iOS bonsoir resolves a peer to its `.local` HOSTNAME
    // (not a numeric IP, as Android's NsdManager does). A hostname placed in an
    // /ip4 multiaddr fails to parse in libp2p, so the LAN dial never happens —
    // build /dns4 (trailing dot stripped) and let libp2p resolve it at dial time.
    test(
      'resolved peer with a .local hostname builds a /dns4 multiaddr',
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
        expect(
          peer!.libp2pAddresses,
          contains('/dns4/Android_9DNYWLJG.local/udp/45000/quic-v1'),
        );
        expect(
          peer.libp2pAddresses,
          contains('/dns4/Android_9DNYWLJG.local/tcp/45001'),
        );
        expect(
          peer.libp2pAddresses.any((a) => a.startsWith('/ip4/')),
          isFalse,
          reason: 'a hostname must never be placed in an /ip4 multiaddr',
        );
      },
    );
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
            (e) =>
                e['event'] == 'LOCAL_MDNS_ADVERTISE_SKIPPED_SUSPECTED_DENIED',
          ),
          hasLength(1),
        );
      },
    );

    test(
      'a resolved peer before the probe keeps the gate OPEN (restart starts)',
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
        expect(
          broadcasts,
          hasLength(2),
          reason: 'gate open → the restart starts a fresh broadcast',
        );
      },
    );

    test(
      'a resolved peer AFTER the gate latches clears it (restart starts)',
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
      },
    );

    test(
      'the gate re-opens after the backoff lapses (single re-probe)',
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
        expect(
          broadcasts,
          hasLength(2),
          reason: 'backoff lapsed → the restart re-probes Local Network',
        );
      },
    );
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

      expect(
        service.debugSuspectedLocalNetworkUnavailable,
        isFalse,
        reason: 'Android has no Local-Network watchdog → never latch',
      );
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
      expect(
        service.discoveredPeers,
        hasLength(1),
        reason: 'browse never gets gated on Android',
      );
    });

    // TC-78-02 (INV-2): on iOS, a latched gate skips the BROADCAST but the
    // browse MUST keep running. Discriminator: in the same restart,
    // DISCOVERY_START present AND ADVERTISE_START absent (proves "browse runs,
    // broadcast gated", not "both run" nor "both skipped").
    test(
      'iOS suspected-denied skips the broadcast but KEEPS the browse running',
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
        expect(
          names,
          contains('LOCAL_MDNS_DISCOVERY_START'),
          reason: 'the browse ALWAYS runs, even while the broadcast is gated',
        );
        expect(
          names,
          isNot(contains('LOCAL_MDNS_ADVERTISE_START')),
          reason: 'the broadcast (re)start is gated on a suspected denial',
        );
        expect(
          names,
          contains('LOCAL_MDNS_ADVERTISE_SKIPPED_SUSPECTED_DENIED'),
          reason: 'the gated-broadcast path is observable as a distinct event',
        );
        expect(
          broadcasts,
          hasLength(1),
          reason: 'no new native broadcast object while the broadcast is gated',
        );
        expect(
          discoveries,
          hasLength(2),
          reason: 'a fresh discovery object — the browse restarted',
        );
      },
    );

    // TC-78-03 (INV-2): the latch SELF-CLEARS on iOS because the browse keeps
    // running — a peer resolves through the still-up browse and clears
    // `_suspectedDeniedUntil`, so the next start re-advertises.
    test(
      'iOS latch self-clears when a peer resolves via the still-running browse',
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
        expect(
          service.debugSuspectedLocalNetworkUnavailable,
          isFalse,
          reason: 'a resolved peer via the live browse clears the latch',
        );

        // The next start re-advertises (broadcast runs again).
        await service.stopAdvertising();
        await service.startAdvertising('me-peer', 54321);
        expect(
          broadcasts,
          hasLength(2),
          reason: 'latch cleared → the broadcast is no longer skipped',
        );
      },
    );

    // TC-78-04 (INV-3, watchdog protection — PRESERVE): on iOS, while latched,
    // the broadcast (re)start MUST still be skipped — this is the 175/0x8BADF00D
    // main-thread-DNS-SD vector protection. Mutation: remove the broadcast gate
    // entirely → this goes red (watchdog vector reopened).
    test(
      'iOS still gates the broadcast on suspected denial (watchdog protection)',
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
        expect(
          names,
          isNot(contains('LOCAL_MDNS_ADVERTISE_START')),
          reason:
              'no native broadcast (re)start while latched (watchdog vector '
              'stays closed)',
        );
        expect(
          names,
          contains('LOCAL_MDNS_ADVERTISE_SKIPPED_SUSPECTED_DENIED'),
        );
        expect(
          broadcasts,
          hasLength(1),
          reason: 'no new native broadcast object created while latched',
        );
      },
    );
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

// The group owns Bonsoir and WS cleanup; P2P owns only its own controllers.
class _ExternallyOwnedLocalP2PService extends LocalP2PService {
  _ExternallyOwnedLocalP2PService({
    required super.discovery,
    required super.wsServer,
  });

  @override
  void dispose() {}
}

class _DiscoveryHealthBridge extends Bridge {
  String relayState = 'online';

  @override
  bool get isInitialized => true;
  @override
  Future<void> initialize() async {}
  @override
  Future<bool> checkHealth() async => true;
  @override
  Future<void> reinitialize() async {}
  @override
  void dispose() {}

  @override
  Future<String> send(String message) async {
    final request = jsonDecode(message) as Map;
    final command = request['cmd'];
    if (command == 'node:start' || command == 'node:status') {
      return jsonEncode({
        'ok': true,
        'peerId': 'self-peer',
        'isStarted': true,
        'listenAddresses': <String>[],
        'circuitAddresses': <String>[],
        'connections': <Object>[],
        'relayState': relayState,
        'healthyRelayCount': relayState == 'online' ? 1 : 0,
      });
    }
    if (command == 'relay:reconnect') {
      relayState = 'online';
      return jsonEncode({
        'ok': true,
        'success': true,
        'recoveryMode': 'in_place',
      });
    }
    if (command == 'inbox:retrieve_pending' || command == 'inbox:retrieve') {
      return jsonEncode({'ok': true, 'messages': [], 'hasMore': false});
    }
    return jsonEncode({'ok': true});
  }
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
  Object? startError;

  _FakeBonsoirDiscovery(this.type);

  void emit(BonsoirDiscoveryEvent event) {
    if (!_controller.isClosed) {
      _controller.add(event);
    }
  }

  void emitError(Object error) => _controller.addError(error);

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
    if (startError != null) {
      throw startError!;
    }
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
  Future<void>? startGate;

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
    await startGate;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
  }
}
