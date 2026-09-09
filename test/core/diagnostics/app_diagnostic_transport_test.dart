import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_app/core/bridge/go_bridge_client.dart';
import 'package:flutter_app/core/diagnostics/app_diagnostics.dart';
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
}
