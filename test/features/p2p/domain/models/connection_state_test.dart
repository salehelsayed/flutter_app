import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart';

void main() {
  group('ConnectionState', () {
    const baseState = ConnectionState(
      peerId: 'peer-1',
      multiaddrs: ['/ip4/127.0.0.1/tcp/4001'],
      direction: 'outbound',
      status: 'connected',
      connectedAt: '2026-01-01T00:00:00.000Z',
    );

    group('fromJson', () {
      test('parses connectedAt as int (Unix ms)', () {
        final state = ConnectionState.fromJson({
          'peerId': 'peer-1',
          'multiaddrs': ['/ip4/127.0.0.1/tcp/4001'],
          'direction': 'inbound',
          'status': 'connected',
          'connectedAt': 1706745600000,
        });
        expect(state.connectedAt, isNotNull);
        expect(state.connectedAt, contains('2024'));
        expect(() => DateTime.parse(state.connectedAt!), returnsNormally);
      });

      test('parses connectedAt as string', () {
        final state = ConnectionState.fromJson({
          'peerId': 'peer-1',
          'multiaddrs': ['/ip4/127.0.0.1/tcp/4001'],
          'direction': 'outbound',
          'status': 'connected',
          'connectedAt': '2026-06-15T12:00:00.000Z',
        });
        expect(state.connectedAt, '2026-06-15T12:00:00.000Z');
      });

      test('connectedAt is null when missing', () {
        final state = ConnectionState.fromJson({
          'peerId': 'peer-1',
          'multiaddrs': ['/ip4/127.0.0.1/tcp/4001'],
          'direction': 'outbound',
          'status': 'connected',
        });
        expect(state.connectedAt, isNull);
      });

      test('defaults direction to outbound when missing', () {
        final state = ConnectionState.fromJson({
          'peerId': 'peer-1',
          'status': 'connected',
        });
        expect(state.direction, 'outbound');
      });

      test('defaults status to connected when missing', () {
        final state = ConnectionState.fromJson({
          'peerId': 'peer-1',
          'direction': 'inbound',
        });
        expect(state.status, 'connected');
      });

      test('defaults multiaddrs to empty list when missing', () {
        final state = ConnectionState.fromJson({'peerId': 'peer-1'});
        expect(state.multiaddrs, isEmpty);
      });

      test('falls back to single address field when multiaddrs missing', () {
        final state = ConnectionState.fromJson({
          'peerId': 'peer-1',
          'address': '/ip4/192.168.1.15/tcp/4001',
        });
        expect(state.multiaddrs, ['/ip4/192.168.1.15/tcp/4001']);
      });
    });

    group('toJson', () {
      test('excludes connectedAt when null', () {
        const state = ConnectionState(
          peerId: 'peer-1',
          multiaddrs: [],
          direction: 'outbound',
          status: 'connected',
        );
        final json = state.toJson();
        expect(json.containsKey('connectedAt'), isFalse);
      });

      test('includes connectedAt when present', () {
        final json = baseState.toJson();
        expect(json['connectedAt'], '2026-01-01T00:00:00.000Z');
      });
    });

    group('equality', () {
      test('equal by peerId, direction, and status only', () {
        const a = ConnectionState(
          peerId: 'peer-1',
          multiaddrs: ['/ip4/1.2.3.4/tcp/4001'],
          direction: 'outbound',
          status: 'connected',
          connectedAt: '2026-01-01T00:00:00.000Z',
        );
        const b = ConnectionState(
          peerId: 'peer-1',
          multiaddrs: ['/ip4/5.6.7.8/tcp/9999'],
          direction: 'outbound',
          status: 'connected',
          connectedAt: '2026-06-15T00:00:00.000Z',
        );
        expect(a, equals(b));
      });

      test('not equal when status differs', () {
        final disconnected = baseState.copyWith(status: 'disconnected');
        expect(baseState, isNot(equals(disconnected)));
      });

      test('hashCode consistent with equality', () {
        const a = ConnectionState(
          peerId: 'peer-1',
          multiaddrs: [],
          direction: 'outbound',
          status: 'connected',
        );
        const b = ConnectionState(
          peerId: 'peer-1',
          multiaddrs: ['/ip4/1.2.3.4/tcp/4001'],
          direction: 'outbound',
          status: 'connected',
          connectedAt: '2026-01-01T00:00:00.000Z',
        );
        expect(a.hashCode, equals(b.hashCode));
      });
    });

    group('copyWith', () {
      test('updates single field and preserves others', () {
        final updated = baseState.copyWith(status: 'disconnected');
        expect(updated.status, 'disconnected');
        expect(updated.peerId, baseState.peerId);
        expect(updated.multiaddrs, baseState.multiaddrs);
        expect(updated.direction, baseState.direction);
        expect(updated.connectedAt, baseState.connectedAt);
      });
    });

    group('toString', () {
      test('contains peerId, direction, and status', () {
        final str = baseState.toString();
        expect(str, contains('peer-1'));
        expect(str, contains('outbound'));
        expect(str, contains('connected'));
      });
    });
  });
}
