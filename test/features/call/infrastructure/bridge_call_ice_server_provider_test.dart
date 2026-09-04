import 'dart:async';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/infrastructure/bridge_call_ice_server_provider.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Bridge implements Bridge {
  @override
  bool get isInitialized => true;

  @override
  Future<String> send(String message) => throw UnimplementedError();

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> checkHealth() async => true;

  @override
  Future<void> reinitialize() async {}

  @override
  void dispose() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final now = DateTime.utc(2026, 8, 30, 12);
  final callId = CallId.parse('22222222-2222-4222-8222-222222222222');

  test(
    'maps one authenticated unexpired TURN bundle without caching it',
    () async {
      var fetches = 0;
      final provider = BridgeCallIceServerProvider(
        bridge: _Bridge(),
        clock: () => now,
        fetch: (_) async {
          fetches++;
          return <String, dynamic>{
            'ok': true,
            'urls': const <String>[
              'turn:relay.invalid:3478?transport=udp',
              'turns:relay.invalid:5349?transport=tcp',
            ],
            'username': 'ephemeral-user',
            'password': 'ephemeral-password',
            'expiresAtMs': now
                .add(const Duration(minutes: 5))
                .millisecondsSinceEpoch,
          };
        },
      );

      final first = await provider.read(callId);
      final second = await provider.read(callId);

      expect(fetches, 2);
      expect(first, hasLength(1));
      expect(second, hasLength(1));
      expect(first.single.urls, hasLength(2));
      expect(first.single.username, 'ephemeral-user');
      expect(first.single.credential, 'ephemeral-password');
      expect(first.single.expiresAt, now.add(const Duration(minutes: 5)));
      expect(first.single.toString(), isNot(contains('ephemeral-user')));
      expect(first.single.toString(), isNot(contains('ephemeral-password')));
    },
  );

  test(
    'fails closed for unavailable, malformed, non-TURN, or expired data',
    () async {
      final responses = <Object>[
        <String, dynamic>{'ok': false},
        <String, dynamic>{
          'ok': true,
          'urls': const <String>['https://relay.invalid'],
          'username': 'user',
          'password': 'password',
          'expiresAtMs': now
              .add(const Duration(minutes: 5))
              .millisecondsSinceEpoch,
        },
        <String, dynamic>{
          'ok': true,
          'urls': const <String>['turn:relay.invalid:3478'],
          'username': 'user',
          'password': 'password',
          'expiresAtMs': now.millisecondsSinceEpoch,
        },
        StateError('unavailable'),
      ];
      var index = 0;
      final provider = BridgeCallIceServerProvider(
        bridge: _Bridge(),
        clock: () => now,
        fetch: (_) async {
          final response = responses[index++];
          if (response is Map<String, dynamic>) return response;
          throw response;
        },
      );

      for (var i = 0; i < responses.length; i++) {
        expect(await provider.read(callId), isEmpty);
      }
    },
  );

  test('bounds an unresponsive native credential fetch', () async {
    final provider = BridgeCallIceServerProvider(
      bridge: _Bridge(),
      clock: () => now,
      requestTimeout: const Duration(milliseconds: 1),
      fetch: (_) => Completer<Map<String, dynamic>>().future,
    );

    expect(await provider.read(callId), isEmpty);
  });
}
