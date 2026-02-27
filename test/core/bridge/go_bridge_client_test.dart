import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/go_bridge_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GoBridgeClient client;
  MethodCall? lastCall;

  /// Default mock handler: records the call and returns a success JSON string.
  String? defaultHandler(MethodCall call) {
    lastCall = call;
    return jsonEncode({'ok': true});
  }

  setUp(() {
    client = GoBridgeClient();
    lastCall = null;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.mknoon/go_bridge'),
      (MethodCall call) async => defaultHandler(call),
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.mknoon/go_bridge'),
      null,
    );
  });

  // ---------------------------------------------------------------------------
  // Command routing: commands WITHOUT payload
  // ---------------------------------------------------------------------------
  group('command routing - no payload', () {
    final noPayloadCmds = <String, String>{
      'identity.generate': 'generateIdentity',
      'mlkem.keygen': 'mlKemKeygen',
      'node:stop': 'stopNode',
      'node:status': 'nodeStatus',
      'relay:reconnect': 'relayReconnect',
      'inbox:retrieve': 'inboxRetrieve',
    };

    for (final entry in noPayloadCmds.entries) {
      test('${entry.key} calls ${entry.value} with no arguments', () async {
        final request = jsonEncode({
          'cmd': entry.key,
          'payload': <String, dynamic>{},
        });

        final response = await client.send(request);
        final decoded = jsonDecode(response) as Map<String, dynamic>;

        expect(decoded['ok'], isTrue);
        expect(lastCall, isNotNull);
        expect(lastCall!.method, equals(entry.value));
        expect(lastCall!.arguments, isNull);
      });
    }
  });

  // ---------------------------------------------------------------------------
  // Command routing: commands WITH payload
  // ---------------------------------------------------------------------------
  group('command routing - with payload', () {
    final payloadCmds = <String, String>{
      'identity.restore': 'restoreIdentity',
      'message.encrypt': 'encryptMessage',
      'message.decrypt': 'decryptMessage',
      'payload.sign': 'signPayload',
      'payload.verify': 'verifyPayload',
      'contactrequest.encrypt': 'encryptContactRequest',
      'contactrequest.decrypt': 'decryptContactRequest',
      'node:start': 'startNode',
      'rendezvous:register': 'rendezvousRegister',
      'rendezvous:discover': 'rendezvousDiscover',
      'relay:probe': 'relayProbe',
      'peer:dial': 'dialPeer',
      'peer:disconnect': 'disconnectPeer',
      'message:send': 'sendMessage',
      'inbox:store': 'inboxStore',
      'inbox:register_token': 'inboxRegisterToken',
      'media:upload': 'mediaUpload',
      'media:download': 'mediaDownload',
      'media:delete': 'mediaDelete',
      'media:list': 'mediaList',
      'profile:upload': 'profileUpload',
      'profile:download': 'profileDownload',
    };

    for (final entry in payloadCmds.entries) {
      test('${entry.key} calls ${entry.value} with payload JSON', () async {
        final payload = {'foo': 'bar', 'num': 42};
        final request = jsonEncode({
          'cmd': entry.key,
          'payload': payload,
        });

        final response = await client.send(request);
        final decoded = jsonDecode(response) as Map<String, dynamic>;

        expect(decoded['ok'], isTrue);
        expect(lastCall, isNotNull);
        expect(lastCall!.method, equals(entry.value));
        // The payload is passed as a JSON-encoded string.
        expect(lastCall!.arguments, isA<String>());
        final passedPayload =
            jsonDecode(lastCall!.arguments as String) as Map<String, dynamic>;
        expect(passedPayload['foo'], equals('bar'));
        expect(passedPayload['num'], equals(42));
      });
    }

    test('payload command with null payload sends no arguments', () async {
      // identity.restore has hasPayload=true, but if payload is null in the
      // request JSON the bridge should invoke the method without arguments.
      final request = jsonEncode({
        'cmd': 'identity.restore',
      });

      final response = await client.send(request);
      final decoded = jsonDecode(response) as Map<String, dynamic>;

      expect(decoded['ok'], isTrue);
      expect(lastCall, isNotNull);
      expect(lastCall!.method, equals('restoreIdentity'));
      expect(lastCall!.arguments, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Error handling
  // ---------------------------------------------------------------------------
  group('error handling', () {
    test('unknown command returns UNKNOWN_COMMAND error', () async {
      final request = jsonEncode({
        'cmd': 'unknown.command',
        'payload': <String, dynamic>{},
      });

      final response = await client.send(request);
      final decoded = jsonDecode(response) as Map<String, dynamic>;

      expect(decoded['ok'], isFalse);
      expect(decoded['errorCode'], equals('UNKNOWN_COMMAND'));
      expect(decoded['errorMessage'], contains('unknown.command'));
      // The MethodChannel should never have been called.
      expect(lastCall, isNull);
    });

    test('null response from native returns NULL_RESPONSE error', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.mknoon/go_bridge'),
        (MethodCall call) async {
          lastCall = call;
          return null;
        },
      );

      final request = jsonEncode({
        'cmd': 'identity.generate',
        'payload': <String, dynamic>{},
      });

      final response = await client.send(request);
      final decoded = jsonDecode(response) as Map<String, dynamic>;

      expect(decoded['ok'], isFalse);
      expect(decoded['errorCode'], equals('NULL_RESPONSE'));
      expect(decoded['errorMessage'], equals('Native bridge returned null'));
      expect(lastCall, isNotNull);
      expect(lastCall!.method, equals('generateIdentity'));
    });

    test('PlatformException returns PLATFORM_ERROR with message', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.mknoon/go_bridge'),
        (MethodCall call) async {
          lastCall = call;
          throw PlatformException(
            code: 'GO_ERROR',
            message: 'something went wrong in Go',
          );
        },
      );

      final request = jsonEncode({
        'cmd': 'node:start',
        'payload': {'listenAddr': '/ip4/0.0.0.0/tcp/0'},
      });

      final response = await client.send(request);
      final decoded = jsonDecode(response) as Map<String, dynamic>;

      expect(decoded['ok'], isFalse);
      expect(decoded['errorCode'], equals('PLATFORM_ERROR'));
      expect(decoded['errorMessage'], equals('something went wrong in Go'));
      expect(lastCall, isNotNull);
      expect(lastCall!.method, equals('startNode'));
    });

    test('PlatformException with null message uses fallback text', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.mknoon/go_bridge'),
        (MethodCall call) async {
          lastCall = call;
          throw PlatformException(code: 'GO_ERROR');
        },
      );

      final request = jsonEncode({
        'cmd': 'node:status',
        'payload': <String, dynamic>{},
      });

      final response = await client.send(request);
      final decoded = jsonDecode(response) as Map<String, dynamic>;

      expect(decoded['ok'], isFalse);
      expect(decoded['errorCode'], equals('PLATFORM_ERROR'));
      expect(decoded['errorMessage'], equals('Platform channel error'));
    });
  });

  // ---------------------------------------------------------------------------
  // Total command coverage sanity check
  // ---------------------------------------------------------------------------
  test('all 28 commands are covered', () async {
    // Exhaustive list of every command in _cmdMap.
    final allCmds = [
      // Identity
      'identity.generate',
      'identity.restore',
      // Crypto
      'mlkem.keygen',
      'message.encrypt',
      'message.decrypt',
      'payload.sign',
      'payload.verify',
      'contactrequest.encrypt',
      'contactrequest.decrypt',
      // Node
      'node:start',
      'node:stop',
      'node:status',
      // Rendezvous
      'rendezvous:register',
      'rendezvous:discover',
      // Relay
      'relay:reconnect',
      'relay:probe',
      // Peer
      'peer:dial',
      'peer:disconnect',
      // Messaging
      'message:send',
      // Inbox
      'inbox:store',
      'inbox:retrieve',
      'inbox:register_token',
      // Media
      'media:upload',
      'media:download',
      'media:delete',
      'media:list',
      // Profile
      'profile:upload',
      'profile:download',
    ];

    expect(allCmds, hasLength(28));

    for (final cmd in allCmds) {
      final request = jsonEncode({
        'cmd': cmd,
        'payload': {'key': 'value'},
      });

      final response = await client.send(request);
      final decoded = jsonDecode(response) as Map<String, dynamic>;
      // Every known command should route successfully (not UNKNOWN_COMMAND).
      expect(decoded['ok'], isTrue, reason: '$cmd should be a known command');
    }
  });
}
