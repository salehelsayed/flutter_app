@Tags(['device'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';
import 'package:flutter_app/core/diagnostics/app_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/diagnostics_backlog_fixture.dart';

/// A same-source fault-injection comparison, runnable on Android and iOS.
/// The Dart collector and archive worker are real. Native diagnostic replies
/// and relay transport are controlled fakes, not a real relay/OS suspension
/// experiment. The independent heartbeat does not use diagnostic timestamps.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  final results = <Map<String, Object?>>[];

  for (final enabled in [false, true]) {
    testWidgets(
      'stalled reconnect recovers with diagnostics ${enabled ? 'on' : 'off'}',
      (tester) async {
        final directory = await Directory.systemTemp.createTemp(
          'diagnostics-reconnect-',
        );
        final now = DateTime.now();
        final seedBytes = await writeDiagnosticsBacklogFixture(
          directory,
          now: now,
          platform: Platform.isIOS ? 'ios' : 'android',
        );
        final bridge = _ControlledBridge();
        var nativeDrains = 0;
        var nativeAcknowledgments = 0;
        var nativeBatchDelivered = false;
        final diagnostics = await AppDiagnostics.installForTesting(
          directory: directory,
          enabled: enabled,
          now: () => now,
          bridge: bridge,
          native: (method, args) async {
            if (method == 'drain') {
              nativeDrains++;
              final deliver = bridge.online && !nativeBatchDelivered;
              if (deliver) nativeBatchDelivered = true;
              return {
                'version': 1,
                'events': <Object?>[
                  if (deliver)
                    for (var index = 0; index < 8; index++)
                      {
                        'schemaVersion': 1,
                        'eventId':
                            '00000000-0000-4000-8000-${(3000000 + index).toRadixString(16).padLeft(12, '0')}',
                        'runId': '00000000-0000-4000-8000-000000200000',
                        'source': Platform.isIOS ? 'ios' : 'android',
                        'platform': Platform.isIOS ? 'ios' : 'android',
                        'sequence': index + 1,
                        'occurredAtMs': now.millisecondsSinceEpoch,
                        'elapsedMs': index,
                        'feature': 'runtime',
                        'stage': 'bridge',
                        'outcome': 'ok',
                        'reason': 'none',
                        'build': 'connectivity-fixture',
                        'values': {'operation': 'relay_reconnect'},
                      },
                ],
                'droppedEvents': 0,
              };
            }
            if (method == 'ack') {
              nativeAcknowledgments += (args['eventIds'] as List).length;
            }
            return true;
          },
        );
        final initial = await diagnostics.status();
        expect(initial['retainedEvents'], enabled ? 9760 : 0);
        expect(seedBytes, greaterThan(4 * 1024 * 1024));
        final beats = <int>[];
        final clock = Stopwatch()..start();
        final heartbeat = Timer.periodic(const Duration(milliseconds: 10), (_) {
          beats.add(clock.elapsedMicroseconds);
        });
        final resumed = ValueNotifier(false);
        await tester.pumpWidget(
          MaterialApp(
            home: ValueListenableBuilder<bool>(
              valueListenable: resumed,
              builder: (_, recovered, _) =>
                  Scaffold(body: Text(recovered ? 'Recovered' : 'Recovering')),
            ),
          ),
        );
        try {
          bridge.online = true;
          diagnostics.attachTransport(bridge: bridge);
          final pendingReconnect = callP2PRelayReconnect(bridge);
          final observedTimeout = expectLater(
            pendingReconnect,
            throwsA(isA<TimeoutException>()),
          );

          // Admit foreground evidence while the independent reconnect is held.
          // Native drains and diagnostic transport are enabled; the latter
          // reports quota/backpressure until the successful recovery retry.
          for (var burst = 0; burst < 20; burst++) {
            final trace = diagnostics.traceForOperation('fixture-$burst');
            for (var event = 0; event < 10; event++) {
              diagnostics.record(
                feature: 'network',
                stage: 'recover',
                outcome: 'failed',
                reason: 'bridge_unavailable',
                traceId: trace,
                values: {'operation': 'relay_reconnect'},
              );
            }
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
          await diagnostics.flush();
          final archive = File('${directory.path}/state.json');
          final beforeRetries = await archive.lastModified();
          for (var resume = 0; resume < 3; resume++) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
            diagnostics.didChangeAppLifecycleState(AppLifecycleState.resumed);
            await diagnostics.flush();
          }
          expect(
            await archive.lastModified(),
            beforeRetries,
            reason: 'No-ACK resume retries must not rewrite the archive',
          );
          await observedTimeout.timeout(const Duration(seconds: 40));
          final stalledElapsedMs = clock.elapsedMilliseconds;
          expect(stalledElapsedMs, lessThan(40000));
          expect(bridge.reconnectCalls, 1);

          // The next recovery owns a fresh response. Releasing the earlier
          // reply later cannot complete or replace this independent result.
          final retryClock = Stopwatch()..start();
          final recovered = await callP2PRelayReconnect(bridge);
          retryClock.stop();
          expect(recovered['ok'], true);
          expect(recovered['attempt'], 2);
          expect(retryClock.elapsedMilliseconds, lessThan(2000));
          bridge.firstReconnect.complete(
            jsonEncode({'ok': false, 'attempt': 1}),
          );
          resumed.value = true;
          await tester.pump();
          expect(find.text('Recovered'), findsOneWidget);
          bridge.backpressure = false;
          diagnostics.didChangeAppLifecycleState(AppLifecycleState.resumed);
          await diagnostics.flush();
          if (enabled) {
            expect(bridge.acceptedIds, isNotEmpty);
            expect(nativeDrains, greaterThan(3));
            expect(nativeAcknowledgments, 8);
          } else {
            expect(bridge.uploadCalls, 0);
          }
          expect(beats.length, greaterThan(100));
          final gaps = [
            for (var index = 1; index < beats.length; index++)
              beats[index] - beats[index - 1],
          ]..sort();
          expect(gaps.last, lessThan(5000000));
          final result = <String, Object?>{
            'platform': Platform.operatingSystem,
            'diagnosticsEnabled': enabled,
            'seedArchiveBytes': seedBytes,
            'initialRetainedEvents': initial['retainedEvents'],
            'stalledReconnectMs': stalledElapsedMs,
            'nextReconnectMs': retryClock.elapsedMilliseconds,
            'heartbeatCount': beats.length,
            'heartbeatMaxGapMs': gaps.last / 1000,
            'heartbeatP95GapMs': gaps[(gaps.length * .95).floor()] / 1000,
            'nativeDiagnosticDrains': nativeDrains,
            'nativeDiagnosticAcknowledgments': nativeAcknowledgments,
            'diagnosticUploadCalls': bridge.uploadCalls,
            'diagnosticAcknowledgments': bridge.acceptedIds.length,
            'nativeAndRelay': 'controlled-fault-injection',
          };
          results.add(result);
          binding.reportData = {'diagnosticsReconnectIsolation': results};
          debugPrint('DIAGNOSTICS_RECONNECT_ISOLATION ${jsonEncode(result)}');
        } finally {
          heartbeat.cancel();
          if (!bridge.firstReconnect.isCompleted) {
            bridge.firstReconnect.complete(jsonEncode({'ok': false}));
          }
          await tester.pumpWidget(const SizedBox.shrink());
          resumed.dispose();
          await diagnostics.dispose();
          await directory.delete(recursive: true);
        }
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
}

final class _ControlledBridge implements Bridge {
  bool online = false;
  bool backpressure = true;
  int reconnectCalls = 0;
  int uploadCalls = 0;
  final firstReconnect = Completer<String>();
  final acceptedIds = <String>{};

  @override
  bool get isInitialized => online;

  @override
  Future<String> send(String message) async {
    final request = jsonDecode(message) as Map;
    if (request['cmd'] == 'relay:reconnect') {
      reconnectCalls++;
      if (reconnectCalls == 1) return firstReconnect.future;
      await Future<void>.delayed(const Duration(milliseconds: 15));
      return jsonEncode({'ok': true, 'attempt': reconnectCalls});
    }
    if (request['cmd'] != 'app_diagnostics_v1') {
      throw StateError('Unexpected command ${request['cmd']}');
    }
    final payload = request['payload'] as Map;
    final ids = <String>[];
    if (payload['op'] == 'upload') {
      uploadCalls++;
      await Future<void>.delayed(const Duration(milliseconds: 25));
      if (!backpressure) {
        ids.addAll(
          (payload['events'] as List).map(
            (event) => event['eventId'] as String,
          ),
        );
        acceptedIds.addAll(ids);
      }
    }
    return jsonEncode({
      'ok': true,
      'data': {
        'supported': true,
        'enabled': payload['enabled'] ?? true,
        'consentEpoch': payload['consentEpoch'],
        'acceptedEventIds': ids,
        if (payload['op'] == 'upload' && backpressure)
          'reason': 'quota_exceeded',
      },
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
