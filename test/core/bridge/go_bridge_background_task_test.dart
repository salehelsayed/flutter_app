import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/go_bridge_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GoBridgeClient client;
  MethodCall? lastCall;

  setUp(() {
    client = GoBridgeClient();
    lastCall = null;
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.mknoon/go_bridge'),
          null,
        );
  });

  group('bg:begin / bg:end MethodChannel contract', () {
    test('bg:begin routes to bgBegin method with no arguments', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.mknoon/go_bridge'),
            (MethodCall call) async {
              lastCall = call;
              // Simulate native returning a task ID string
              return '12345';
            },
          );

      final response = await client.send(
        jsonEncode({'cmd': 'bg:begin'}),
      );

      expect(lastCall, isNotNull);
      expect(lastCall!.method, equals('bgBegin'));
      expect(lastCall!.arguments, isNull,
          reason: 'bg:begin has hasPayload=false, no arguments');
      // GoBridgeClient.send() returns the raw string from native
      expect(response, equals('12345'));
    });

    test('bg:end routes to bgEnd method with JSON payload', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.mknoon/go_bridge'),
            (MethodCall call) async {
              lastCall = call;
              return null; // bgEnd returns nil on success
            },
          );

      final response = await client.send(
        jsonEncode({
          'cmd': 'bg:end',
          'payload': {'taskId': '12345'},
        }),
      );

      expect(lastCall, isNotNull);
      expect(lastCall!.method, equals('bgEnd'));
      // Payload is JSON-encoded by GoBridgeClient before invokeMethod
      expect(lastCall!.arguments, isA<String>());
      final passedPayload =
          jsonDecode(lastCall!.arguments as String) as Map<String, dynamic>;
      expect(passedPayload['taskId'], equals('12345'));
      // Null native response → NULL_RESPONSE error JSON
      final decoded = jsonDecode(response) as Map<String, dynamic>;
      expect(decoded['errorCode'], equals('NULL_RESPONSE'));
    });

    test('bg:begin with empty-string response signals OS refused', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.mknoon/go_bridge'),
            (MethodCall call) async {
              lastCall = call;
              return ''; // OS refused to grant background time
            },
          );

      final response = await client.send(
        jsonEncode({'cmd': 'bg:begin'}),
      );

      expect(lastCall!.method, equals('bgBegin'));
      // Empty string means "no task granted" — caller checks isEmpty
      expect(response, equals(''));
    });

    test('bg:begin with PlatformException returns PLATFORM_ERROR', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.mknoon/go_bridge'),
            (MethodCall call) async {
              throw PlatformException(
                code: 'UNAVAILABLE',
                message: 'background task not available',
              );
            },
          );

      final response = await client.send(
        jsonEncode({'cmd': 'bg:begin'}),
      );

      final decoded = jsonDecode(response) as Map<String, dynamic>;
      expect(decoded['ok'], isFalse);
      expect(decoded['errorCode'], equals('PLATFORM_ERROR'));
      expect(decoded['errorMessage'],
          equals('background task not available'));
    });

    test('bg:begin with MissingPluginException returns MISSING_PLUGIN',
        () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.mknoon/go_bridge'),
            (MethodCall call) async {
              throw MissingPluginException(
                'No implementation found for bgBegin',
              );
            },
          );

      final response = await client.send(
        jsonEncode({'cmd': 'bg:begin'}),
      );

      final decoded = jsonDecode(response) as Map<String, dynamic>;
      expect(decoded['ok'], isFalse);
      expect(decoded['errorCode'], equals('MISSING_PLUGIN'));
      expect(decoded['errorMessage'], contains('bgBegin'));
    });

    test('concurrent bg:begin calls each invoke bgBegin independently',
        () async {
      var callCount = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.mknoon/go_bridge'),
            (MethodCall call) async {
              callCount++;
              return callCount.toString(); // unique task ID per call
            },
          );

      final futures = List.generate(
        3,
        (_) => client.send(jsonEncode({'cmd': 'bg:begin'})),
      );
      final results = await Future.wait(futures);

      expect(callCount, equals(3));
      // Each should get a unique task ID
      final ids = results.toSet();
      expect(ids, hasLength(3),
          reason: 'Each concurrent bg:begin must get its own task ID');
    });
  });
}
