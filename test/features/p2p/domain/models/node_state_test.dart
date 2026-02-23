import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart';

void main() {
  const testPeerId = '12D3KooWTestPeerIdABCDEF';

  NodeState makeNodeState({
    String? peerId = testPeerId,
    bool isStarted = true,
    List<String>? listenAddresses,
    List<String>? circuitAddresses,
    List<ConnectionState>? connections,
    List<String>? registeredNamespaces,
  }) {
    return NodeState(
      peerId: peerId,
      isStarted: isStarted,
      listenAddresses: listenAddresses ?? ['/ip4/127.0.0.1/tcp/4001'],
      circuitAddresses: circuitAddresses ?? ['/p2p-circuit/peer-abc'],
      connections: connections ??
          [
            const ConnectionState(
              peerId: 'peer-conn-1',
              multiaddrs: ['/ip4/192.168.1.1/tcp/4001'],
              direction: 'outbound',
              status: 'connected',
              connectedAt: '2026-01-15T12:00:00.000Z',
            ),
          ],
      registeredNamespaces:
          registeredNamespaces ?? ['mknoon/contact-request'],
    );
  }

  group('NodeState', () {
    group('fromJson / toJson', () {
      test('round-trips correctly with all fields', () {
        final original = makeNodeState();
        final json = original.toJson();
        final restored = NodeState.fromJson(json);

        expect(restored.peerId, original.peerId);
        expect(restored.isStarted, original.isStarted);
        expect(restored.listenAddresses, original.listenAddresses);
        expect(restored.circuitAddresses, original.circuitAddresses);
        expect(restored.connections.length, original.connections.length);
        expect(
            restored.connections.first.peerId, original.connections.first.peerId);
        expect(restored.registeredNamespaces, original.registeredNamespaces);
      });

      test('defaults for missing lists', () {
        final json = <String, dynamic>{
          'peerId': testPeerId,
          'isStarted': true,
        };

        final restored = NodeState.fromJson(json);

        expect(restored.peerId, testPeerId);
        expect(restored.isStarted, isTrue);
        expect(restored.listenAddresses, isEmpty);
        expect(restored.circuitAddresses, isEmpty);
        expect(restored.connections, isEmpty);
        expect(restored.registeredNamespaces, isEmpty);
      });

      test('handles null peerId', () {
        final json = <String, dynamic>{
          'isStarted': false,
        };

        final restored = NodeState.fromJson(json);
        expect(restored.peerId, isNull);
        expect(restored.isStarted, isFalse);
      });

      test('defaults isStarted to false when missing', () {
        final json = <String, dynamic>{
          'peerId': testPeerId,
        };

        final restored = NodeState.fromJson(json);
        expect(restored.isStarted, isFalse);
      });

      test('round-trips nested ConnectionState list', () {
        final original = makeNodeState(
          connections: [
            const ConnectionState(
              peerId: 'peer-a',
              multiaddrs: ['/ip4/10.0.0.1/tcp/4001'],
              direction: 'inbound',
              status: 'connected',
              connectedAt: '2026-02-01T10:00:00.000Z',
            ),
            const ConnectionState(
              peerId: 'peer-b',
              multiaddrs: ['/ip4/10.0.0.2/tcp/4001'],
              direction: 'outbound',
              status: 'disconnected',
            ),
          ],
        );

        final json = original.toJson();
        final restored = NodeState.fromJson(json);

        expect(restored.connections.length, 2);
        expect(restored.connections[0].peerId, 'peer-a');
        expect(restored.connections[0].direction, 'inbound');
        expect(
            restored.connections[0].connectedAt, '2026-02-01T10:00:00.000Z');
        expect(restored.connections[1].peerId, 'peer-b');
        expect(restored.connections[1].status, 'disconnected');
      });
    });

    group('NodeState.stopped', () {
      test('isStarted is false', () {
        expect(NodeState.stopped.isStarted, isFalse);
      });

      test('peerId is null', () {
        expect(NodeState.stopped.peerId, isNull);
      });

      test('all lists are empty', () {
        expect(NodeState.stopped.listenAddresses, isEmpty);
        expect(NodeState.stopped.circuitAddresses, isEmpty);
        expect(NodeState.stopped.connections, isEmpty);
        expect(NodeState.stopped.registeredNamespaces, isEmpty);
      });
    });

    group('copyWith', () {
      test('updates isStarted and preserves other fields', () {
        final original = makeNodeState();
        final updated = original.copyWith(isStarted: false);

        expect(updated.isStarted, isFalse);
        expect(updated.peerId, original.peerId);
        expect(updated.listenAddresses, original.listenAddresses);
        expect(updated.circuitAddresses, original.circuitAddresses);
        expect(updated.connections.length, original.connections.length);
        expect(updated.registeredNamespaces, original.registeredNamespaces);
      });

      test('updates peerId', () {
        final original = makeNodeState();
        final updated = original.copyWith(peerId: 'new-peer-id');

        expect(updated.peerId, 'new-peer-id');
        expect(updated.isStarted, original.isStarted);
      });

      test('updates listenAddresses', () {
        final original = makeNodeState();
        final newAddresses = ['/ip4/0.0.0.0/tcp/5001'];
        final updated = original.copyWith(listenAddresses: newAddresses);

        expect(updated.listenAddresses, newAddresses);
        expect(updated.peerId, original.peerId);
      });
    });

    group('toString', () {
      test('includes peerId and isStarted', () {
        final state = makeNodeState();
        final str = state.toString();

        expect(str, contains(testPeerId));
        expect(str, contains('isStarted: true'));
      });

      test('includes connection count', () {
        final state = makeNodeState();
        final str = state.toString();

        expect(str, contains('connections: 1'));
      });
    });
  });
}
