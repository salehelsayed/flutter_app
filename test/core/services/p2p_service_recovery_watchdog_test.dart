import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../shared/fakes/in_memory_inbox_staging_repository.dart';

class _RecoveryBridge extends Bridge {
  String relayState = 'online';
  Completer<String>? reconnect;
  Completer<String>? status;
  final commands = <String>[];

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

  Map<String, Object?> get nodeState => {
    'ok': true,
    'peerId': 'self-peer',
    'isStarted': true,
    'listenAddresses': <String>[],
    'circuitAddresses': <String>[],
    'connections': <Object>[],
    'relayState': relayState,
    'healthyRelayCount': relayState == 'online' ? 1 : 0,
  };

  @override
  Future<String> send(String message) async {
    final command = (jsonDecode(message) as Map)['cmd'] as String;
    commands.add(command);
    if (command == 'node:status') {
      return status?.future ?? jsonEncode(nodeState);
    }
    if (command == 'node:start') return jsonEncode(nodeState);
    if (command == 'relay:reconnect') {
      return reconnect?.future ??
          jsonEncode({'ok': true, 'success': true, 'recoveryMode': 'in_place'});
    }
    if (command == 'inbox:retrieve_pending') {
      return jsonEncode({'ok': true, 'messages': [], 'hasMore': false});
    }
    return jsonEncode({'ok': true});
  }
}

void main() {
  setUp(() => flowEventLoggingEnabled = false);
  tearDown(() => flowEventLoggingEnabled = true);

  for (final reconnect in [false, true]) {
    test(
      'stalled ${reconnect ? 'reconnect' : 'status'} bridge has a deadline',
      () {
        fakeAsync((clock) {
          final bridge = _RecoveryBridge();
          final pending = Completer<String>();
          if (reconnect) {
            bridge.reconnect = pending;
          } else {
            bridge.status = pending;
          }
          Object? failure;
          var completed = false;
          final future = reconnect
              ? callP2PRelayReconnect(bridge)
              : callP2PNodeStatus(bridge);
          unawaited(
            future.then<void>(
              (_) => completed = true,
              onError: (Object e) {
                completed = true;
                failure = e;
              },
            ),
          );
          clock.flushMicrotasks();
          final deadline = reconnect
              ? const Duration(seconds: 30) + p2pBridgeWatchdogMargin
              : const Duration(seconds: 5);
          clock.elapse(deadline - const Duration(milliseconds: 1));
          expect(
            completed,
            isFalse,
            reason: 'preserve the native operation budget',
          );
          clock.elapse(const Duration(milliseconds: 1));
          expect(
            completed,
            isTrue,
            reason: 'a missing native reply cannot pin recovery',
          );
          expect(failure, isA<TimeoutException>());
          pending.complete(jsonEncode({'ok': true}));
          clock.flushMicrotasks();
          expect(
            failure,
            isA<TimeoutException>(),
            reason: 'late reply cannot replace timeout',
          );
        });
      },
    );
  }

  for (final stalledOperation in ['relay:reconnect', 'node:status']) {
    test(
      '$stalledOperation timeout releases coalesced health checks and permits retry',
      () {
        fakeAsync((clock) {
          final bridge = _RecoveryBridge();
          final service = P2PServiceImpl(
            bridge: bridge,
            inboxStagingRepository: InMemoryInboxStagingRepository(),
          );
          var ready = false;
          unawaited(() async {
            await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');
            await service.performImmediateHealthCheck();
            ready = true;
          }());
          clock.flushMicrotasks();
          expect(ready, isTrue);
          bridge.commands.clear();
          final pending = Completer<String>();
          bridge.relayState = 'degraded';
          if (stalledOperation == 'relay:reconnect') {
            bridge.reconnect = pending;
          } else {
            bridge.status = pending;
          }
          var firstDone = false;
          var joinedDone = false;
          unawaited(
            service.performImmediateHealthCheck().then((_) => firstDone = true),
          );
          clock.flushMicrotasks();
          unawaited(
            service.performImmediateHealthCheck().then(
              (_) => joinedDone = true,
            ),
          );
          clock.flushMicrotasks();
          expect(firstDone, isFalse);
          expect(joinedDone, isFalse);
          expect(
            bridge.commands.where((c) => c == stalledOperation),
            hasLength(1),
          );

          clock.elapse(
            stalledOperation == 'relay:reconnect'
                ? const Duration(milliseconds: 30500)
                : const Duration(seconds: 5),
          );
          expect(
            firstDone,
            isTrue,
            reason: 'foreground recovery must release its owner',
          );
          expect(
            joinedDone,
            isTrue,
            reason: 'resume must not keep joining an expired await',
          );
          if (stalledOperation == 'relay:reconnect') {
            expect(service.consecutiveRefreshFailures, 1);
            expect(
              bridge.commands,
              contains('inbox:retrieve_pending'),
              reason: 'a timed-out reconnect must not starve the inbox',
            );
          }

          bridge.reconnect = null;
          bridge.status = null;
          bridge.relayState = 'online';
          bridge.commands.clear();
          var retryDone = false;
          unawaited(
            service.performImmediateHealthCheck().then((_) => retryDone = true),
          );
          clock.flushMicrotasks();
          expect(retryDone, isTrue);
          expect(bridge.commands, contains('node:status'));
          expect(service.currentState.relayState, 'online');
          final recoveryMethod = service.lastRecoveryMethod;
          pending.complete(
            jsonEncode({
              ...bridge.nodeState,
              'recoveryMode': 'watchdog_restart',
              'success': true,
            }),
          );
          clock.flushMicrotasks();
          expect(
            service.lastRecoveryMethod,
            recoveryMethod,
            reason:
                'expired native completion must not mutate fresh recovery state',
          );
          service.dispose();
        });
      },
    );
  }
}
