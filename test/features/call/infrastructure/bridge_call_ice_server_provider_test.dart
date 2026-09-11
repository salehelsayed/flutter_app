import 'dart:async';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/features/call/application/call_negotiation_effect_executor.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/diagnostics/call_diagnostics.dart';
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
    'TURN diagnostics distinguish refused malformed and timed out credentials',
    () async {
      final diagnostics = await CallDiagnostics.installForTesting();
      addTearDown(() async {
        await diagnostics.setEnabled(false);
        await diagnostics.dispose();
      });
      final trace = diagnostics.beginAttempt()!;
      diagnostics.bindCall(callId: callId.value, traceId: trace);
      for (final response in <Map<String, dynamic>?>[
        {'ok': false, 'errorCode': 'TURN_CREDENTIALS_REJECTED'},
        {'ok': true, 'username': 'private-credential'},
        null,
      ]) {
        final provider = BridgeCallIceServerProvider(
          bridge: _Bridge(),
          clock: () => now,
          requestTimeout: const Duration(milliseconds: 1),
          fetch: (_) async =>
              response ?? await Completer<Map<String, dynamic>>().future,
        );
        if (response == null) {
          expect(await provider.read(callId), isEmpty);
        } else {
          await expectLater(
            provider.read(callId),
            throwsA(isA<CallNegotiationPortException>()),
          );
        }
      }
      final events = (await diagnostics.eventsForTesting())
          .where((event) => event['stage'] == 'turn')
          .toList();
      expect(events.where((event) => event['outcome'] == 'ok'), isEmpty);
      expect(
        events
            .where((event) => event['outcome'] == 'failed')
            .map((event) => event['reason']),
        ['turn_credential_failed', 'malformed_response', 'timeout'],
      );
      expect(events, everyElement(containsPair('traceId', trace)));
      expect(
        await diagnostics.exportPreview(),
        isNot(contains('private-credential')),
      );
    },
  );

  test('refreshes the authenticated TURN bundle on every read', () async {
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
  });

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
        await expectLater(
          provider.read(callId),
          throwsA(isA<CallNegotiationPortException>()),
        );
      }
    },
  );

  test(
    'cached TURN never hides rejection and is owned by one live call',
    () async {
      final pending = Completer<Map<String, dynamic>>();
      var reads = 0;
      final provider = BridgeCallIceServerProvider(
        bridge: _Bridge(),
        clock: () => now,
        fetch: (_) async {
          reads++;
          if (reads == 1) {
            return {
              'ok': true,
              'urls': ['turn:relay.invalid:3478'],
              'username': 'fixture',
              'password': 'fixture',
              'expiresAtMs': now
                  .add(const Duration(minutes: 5))
                  .millisecondsSinceEpoch,
            };
          }
          if (reads == 2) {
            return {'ok': false, 'errorCode': 'TURN_CREDENTIALS_REJECTED'};
          }
          return pending.future;
        },
      );
      expect(await provider.read(callId), hasLength(1));
      await expectLater(
        provider.read(callId),
        throwsA(isA<CallNegotiationPortException>()),
      );
      final other = CallId.parse('33333333-3333-4333-8333-333333333333');
      await expectLater(
        provider.read(other),
        throwsA(isA<CallNegotiationPortException>()),
      );
      final late = provider.read(callId);
      final rejected = expectLater(
        late,
        throwsA(isA<CallNegotiationPortException>()),
      );
      provider.close();
      pending.complete({
        'ok': false,
        'errorCode': 'TURN_CREDENTIALS_UNAVAILABLE',
      });
      await rejected;
      await expectLater(
        provider.read(callId),
        throwsA(isA<CallNegotiationPortException>()),
      );
      expect(reads, 3);
    },
  );

  test('bounds unresponsive fetch and ignores late data and late errors', () {
    for (final fails in [false, true]) {
      fakeAsync((time) {
        final pending = Completer<Map<String, dynamic>>();
        final provider = BridgeCallIceServerProvider(
          bridge: _Bridge(),
          clock: () => now.add(time.elapsed),
          fetch: (_) => pending.future,
        );
        var completions = 0;
        unawaited(
          provider.read(callId).then((servers) {
            expect(servers, isEmpty);
            completions++;
          }),
        );
        time.flushMicrotasks();
        time.elapse(const Duration(milliseconds: 4999));
        expect(completions, 0);
        time.elapse(const Duration(milliseconds: 1));
        expect(completions, 1);
        if (fails) {
          pending.completeError(StateError('private'));
        } else {
          pending.complete({'ok': true, 'username': 'private'});
        }
        time.flushMicrotasks();
        expect(completions, 1);
      });
    }
  });
}
