import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/p2p/application/discover_peer_use_case.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/discovered_peer.dart';
import '../../../core/services/fake_p2p_service.dart';

/// FakeP2PService subclass that throws on discoverPeer().
class _ThrowingDiscoverFakeP2PService extends FakeP2PService {
  _ThrowingDiscoverFakeP2PService({super.initialState});

  @override
  Future<DiscoveredPeer?> discoverPeer(String peerId) async {
    discoverPeerCallCount++;
    lastDiscoverPeerId = peerId;
    throw Exception('discover exploded');
  }
}

/// FakeP2PService subclass that throws on dialPeer().
class _ThrowingDialFakeP2PService extends FakeP2PService {
  _ThrowingDialFakeP2PService({super.initialState});

  @override
  Future<bool> dialPeer(String peerId, {List<String>? addresses}) async {
    dialPeerCallCount++;
    lastDialPeerId = peerId;
    throw Exception('dial exploded');
  }
}

void main() {
  const startedState = NodeState(isStarted: true, peerId: 'my-peer');

  group('discoverP2PPeer', () {
    test('returns nodeNotRunning when node is stopped', () async {
      final p2pService = FakeP2PService(); // default: NodeState.stopped

      final (result, peer) = await discoverP2PPeer(
        p2pService: p2pService,
        peerId: 'target-peer',
      );

      expect(result, DiscoverPeerResult.nodeNotRunning);
      expect(peer, isNull);
    });

    test('returns notFound when discoverPeer returns null', () async {
      final p2pService = FakeP2PService(
        initialState: startedState,
        discoverPeerResult: null,
      );

      final (result, peer) = await discoverP2PPeer(
        p2pService: p2pService,
        peerId: 'target-peer',
      );

      expect(result, DiscoverPeerResult.notFound);
      expect(peer, isNull);
    });

    test('returns success with DiscoveredPeer when found', () async {
      const foundPeer = DiscoveredPeer(
        id: 'target-peer',
        addresses: ['/ip4/127.0.0.1/tcp/4001'],
      );
      final p2pService = FakeP2PService(
        initialState: startedState,
        discoverPeerResult: foundPeer,
      );

      final (result, peer) = await discoverP2PPeer(
        p2pService: p2pService,
        peerId: 'target-peer',
      );

      expect(result, DiscoverPeerResult.success);
      expect(peer, isNotNull);
      expect(peer!.id, 'target-peer');
      expect(peer.addresses, ['/ip4/127.0.0.1/tcp/4001']);
    });

    test('returns error when discoverPeer throws', () async {
      final p2pService = _ThrowingDiscoverFakeP2PService(
        initialState: startedState,
      );

      final (result, peer) = await discoverP2PPeer(
        p2pService: p2pService,
        peerId: 'target-peer',
      );

      expect(result, DiscoverPeerResult.error);
      expect(peer, isNull);
    });
  });

  group('dialP2PPeer', () {
    test('returns false when node is stopped', () async {
      final p2pService = FakeP2PService(); // default: NodeState.stopped

      final result = await dialP2PPeer(
        p2pService: p2pService,
        peerId: 'target-peer',
      );

      expect(result, false);
    });

    test('returns true when dialPeer succeeds', () async {
      final p2pService = FakeP2PService(
        initialState: startedState,
        dialPeerResult: true,
      );

      final result = await dialP2PPeer(
        p2pService: p2pService,
        peerId: 'target-peer',
        addresses: ['/ip4/127.0.0.1/tcp/4001'],
      );

      expect(result, true);
    });

    test('returns false when dialPeer fails', () async {
      final p2pService = FakeP2PService(
        initialState: startedState,
        dialPeerResult: false,
      );

      final result = await dialP2PPeer(
        p2pService: p2pService,
        peerId: 'target-peer',
      );

      expect(result, false);
    });

    test('returns false when dialPeer throws', () async {
      final p2pService = _ThrowingDialFakeP2PService(
        initialState: startedState,
      );

      final result = await dialP2PPeer(
        p2pService: p2pService,
        peerId: 'target-peer',
      );

      expect(result, false);
    });
  });
}
