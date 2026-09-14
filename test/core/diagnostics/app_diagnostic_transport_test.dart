import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_app/core/bridge/go_bridge_client.dart';
import 'package:flutter_app/core/diagnostics/app_diagnostics.dart';
import 'package:flutter_app/core/diagnostics/local_connection_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.mknoon/go_bridge');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  test(
    'production collector sends exact native payloads and typed bridge failures',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'app-transport-test-',
      );
      final bridge = GoBridgeClient();
      final requests = <Map<String, dynamic>>[];
      const codec = StandardMethodCodec();
      messenger.setMockMessageHandler(
        'com.mknoon/go_bridge_events',
        (_) async => codec.encodeSuccessEnvelope(null),
      );
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'dialPeer') {
          throw MissingPluginException('SECRET_PATH');
        }
        expect(call.method, 'appDiagnosticsV1');
        final request =
            jsonDecode(call.arguments as String) as Map<String, dynamic>;
        expect(request.containsKey('cmd'), false);
        requests.add(request);
        return jsonEncode({
          'ok': true,
          'data': {
            'supported': true,
            'enabled': request['enabled'] ?? true,
            'consentEpoch': request['consentEpoch'],
            'acceptedEventIds': (request['events'] as List? ?? [])
                .map((e) => e['eventId'])
                .toList(),
          },
        });
      });
      await bridge.initialize();
      final diagnostics = AppDiagnostics.instance;
      var networkChecks = 0;
      diagnostics.attachTransport(
        bridge: bridge,
        networkAllowed: () async {
          networkChecks++;
          return true;
        },
      );
      await diagnostics.initialize(directory: directory, useNative: false);
      addTearDown(() async {
        await diagnostics.dispose();
        bridge.dispose();
        await Future<void>.delayed(Duration.zero);
        messenger.setMockMethodCallHandler(channel, null);
        messenger.setMockMessageHandler('com.mknoon/go_bridge_events', null);
        await directory.delete(recursive: true);
      });
      final trace = diagnostics.startAttempt(feature: 'message');
      diagnostics.finishAttempt(
        feature: 'message',
        traceId: trace,
        outcome: 'success',
      );
      await diagnostics.flush();
      expect(
        networkChecks,
        greaterThan(0),
        reason: 'initialization must retain an already attached privacy gate',
      );
      expect(requests.first['op'], 'configure');
      expect(requests.any((r) => r['op'] == 'upload'), true);
      final response =
          jsonDecode(
                await bridge.send(
                  jsonEncode({
                    'cmd': 'peer:dial',
                    'payload': {'peerId': 'SECRET_PEER_ID'},
                  }),
                ),
              )
              as Map;
      expect(response['errorCode'], 'MISSING_PLUGIN');
      final network = (await diagnostics.eventsForTesting())
          .where((e) => e['feature'] == 'network' && e['stage'] == 'finish')
          .single;
      expect(network['reason'], 'bridge_handler_missing');
      expect(network['outcome'], 'failed');
      expect(await diagnostics.exportPreview(), isNot(contains('SECRET')));
    },
  );
  const connection = <String, Object?>{
    'connectionStage': 'stream_opened',
    'connectionOutcome': 'ok',
    'addressFamily': 'ipv4',
    'transportProtocol': 'tcp',
    'pathClass': 'direct',
    'observedLeg': 'endpoint_to_peer',
    'familyFallback': 'unknown',
  };

  test(
    'native observation admission bounds rows rejects sensitive fields and contains sink failures',
    () {
      final accepted = <Map<String, Object?>>[];
      observeConnectionDiagnostics([
        {...connection, 'address': 'PRIVATE'},
        {...connection, 'addressFamily': '192.0.2.1'},
        {...connection, 'transportProtocol': null},
        'PRIVATE',
        connection,
      ], accepted.add);
      expect(accepted, [connection]);
      observeConnectionDiagnostics(List.filled(1000, connection), accepted.add);
      expect(accepted, hasLength(13));
      expect(
        () => observeConnectionDiagnostics([
          connection,
        ], (_) => throw StateError('PRIVATE')),
        returnsNormally,
      );
    },
  );

  for (final mode in ['enabled', 'disabled', 'broken storage']) {
    test(
      'message results and inbox acceptance stay independent of diagnostics: $mode',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'connection-diag-',
        );
        final diagnostics = await AppDiagnostics.installForTesting(
          directory: directory,
          enabled: mode != 'disabled',
          upload: (_) async => {},
          persist: mode == 'broken storage'
              ? (_, _) async => throw StateError('PRIVATE')
              : null,
        );
        final bridge = GoBridgeClient();
        const codec = StandardMethodCodec();
        messenger.setMockMessageHandler(
          'com.mknoon/go_bridge_events',
          (_) async => codec.encodeSuccessEnvelope(null),
        );
        messenger.setMockMethodCallHandler(
          channel,
          (call) async => jsonEncode(
            call.method == 'inboxStore'
                ? {'ok': true, 'storeStatus': 'stored'}
                : {
                    'ok': true,
                    'sent': true,
                    'acked': false,
                    'reply': 'PRIVATE',
                    'connectionDiagnostics': [
                      connection,
                      {
                        ...connection,
                        'connectionStage': 'recipient_ack',
                        'connectionOutcome': 'unknown',
                      },
                    ],
                  },
          ),
        );
        await bridge.initialize();
        addTearDown(() async {
          await diagnostics.dispose();
          bridge.dispose();
          await Future<void>.delayed(Duration.zero);
          messenger.setMockMethodCallHandler(channel, null);
          messenger.setMockMessageHandler('com.mknoon/go_bridge_events', null);
          if (await directory.exists()) await directory.delete(recursive: true);
        });
        String? messageTrace;
        await diagnostics.runWithAttempt(
          feature: 'message',
          body: (trace) async {
            messageTrace = trace;
            final sent =
                jsonDecode(
                      await bridge.send(
                        jsonEncode({
                          'cmd': 'message:send',
                          'payload': {
                            'peerId': 'PRIVATE',
                            'message': 'PRIVATE',
                          },
                        }),
                      ),
                    )
                    as Map;
            expect(sent['ok'], isTrue);
            expect(sent['sent'], isTrue);
            expect(sent['acked'], isFalse);
            final stored =
                jsonDecode(
                      await bridge.send(
                        jsonEncode({
                          'cmd': 'inbox:store',
                          'payload': {
                            'peerId': 'PRIVATE',
                            'message': 'PRIVATE',
                          },
                        }),
                      ),
                    )
                    as Map;
            expect(stored, {'ok': true, 'storeStatus': 'stored'});
          },
        );
        final events = await diagnostics.eventsForTesting();
        if (mode == 'enabled') {
          final stream = events.singleWhere(
            (e) => (e['values'] as Map)['connectionStage'] == 'stream_opened',
          );
          expect(stream['traceId'], messageTrace);
          expect(stream['values'], connection);
          expect(
            events.singleWhere((e) => e['stage'] == 'receipt')['outcome'],
            'unknown',
          );
          final stored = events.singleWhere((e) => e['stage'] == 'store');
          expect(stored['values'], {
            'connectionStage': 'inbox_acceptance',
            'connectionOutcome': 'ok',
          });
          expect(stored['values'], isNot(contains('acknowledged')));
        } else {
          expect(
            events.where(
              (e) => (e['values'] as Map).containsKey('connectionStage'),
            ),
            isEmpty,
          );
        }
        expect(await diagnostics.exportPreview(), isNot(contains('PRIVATE')));
      },
    );
  }
}
