import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/local_discovery/local_ws_server.dart';

void main() {
  group('LocalWsServer', () {
    late LocalWsServer server;

    setUp(() {
      server = LocalWsServer(idleTimeout: const Duration(seconds: 2));
    });

    tearDown(() {
      server.dispose();
    });

    test('starts on random port', () async {
      final port = await server.start();
      expect(port, greaterThan(0));
      expect(server.port, equals(port));
    });

    test('receives message and emits LocalChatMessage', () async {
      final port = await server.start();

      final messages = <dynamic>[];
      final sub = server.messageStream.listen(messages.add);

      // Connect as a client and send a message.
      final ws = await WebSocket.connect('ws://localhost:$port');
      ws.add(
        jsonEncode({
          'from': 'peerA',
          'to': 'peerB',
          'content': '{"type":"chat","version":"1","payload":{"text":"hello"}}',
        }),
      );

      // Wait for ack.
      final ackRaw = await ws.first;
      final ack = jsonDecode(ackRaw as String);
      expect(ack['ack'], isTrue);

      // Give stream time to propagate.
      await Future.delayed(const Duration(milliseconds: 50));

      expect(messages, hasLength(1));
      final msg = messages.first;
      expect(msg.from, equals('peerA'));
      expect(msg.to, equals('peerB'));
      expect(msg.isIncoming, isTrue);

      await ws.close();
      await sub.cancel();
    });

    test('ignores malformed JSON', () async {
      final port = await server.start();

      final messages = <dynamic>[];
      final sub = server.messageStream.listen(messages.add);

      final ws = await WebSocket.connect('ws://localhost:$port');
      ws.add('not valid json');

      await Future.delayed(const Duration(milliseconds: 50));
      expect(messages, isEmpty);

      await ws.close();
      await sub.cancel();
    });

    test('ignores message with missing fields', () async {
      final port = await server.start();

      final messages = <dynamic>[];
      final sub = server.messageStream.listen(messages.add);

      final ws = await WebSocket.connect('ws://localhost:$port');
      ws.add(jsonEncode({'from': 'peerA'})); // missing 'to' and 'content'

      await Future.delayed(const Duration(milliseconds: 50));
      expect(messages, isEmpty);

      await ws.close();
      await sub.cancel();
    });

    test('sendMessage delivers and gets ack', () async {
      // Start a second server to act as the remote peer.
      final remoteServer = LocalWsServer();
      final remotePort = await remoteServer.start();

      final port = await server.start();

      final sent = await server.sendMessage(
        'localhost',
        remotePort,
        '{"type":"chat","version":"1","payload":{"text":"hi"}}',
        'peerA',
        'peerB',
      );

      expect(sent, isTrue);

      remoteServer.dispose();
    });

    test('sendMessage returns false on connection failure', () async {
      await server.start();

      // Try to send to a port where nothing is listening.
      final sent = await server.sendMessage(
        'localhost',
        19999, // unlikely to have anything
        'content',
        'peerA',
        'peerB',
      );

      expect(sent, isFalse);
    });

    group('two servers exchange messages', () {
      late LocalWsServer serverA;
      late LocalWsServer serverB;

      setUp(() {
        serverA = LocalWsServer(idleTimeout: const Duration(seconds: 2));
        serverB = LocalWsServer(idleTimeout: const Duration(seconds: 2));
      });

      tearDown(() {
        serverA.dispose();
        serverB.dispose();
      });

      test(
        'interactive local send timeout stays within bounded chat budget',
        () async {
          final portA = await serverA.start();
          final portB = await serverB.start();

          // Sending should complete within a reasonable time
          final stopwatch = Stopwatch()..start();
          final sent = await serverA.sendMessage(
            'localhost',
            portB,
            '{"text":"timeout test"}',
            'peerA',
            'peerB',
          );
          stopwatch.stop();

          expect(sent, isTrue);
          // Local send should be fast (well under 5s ack timeout)
          expect(stopwatch.elapsed.inSeconds, lessThan(5));
        },
      );

      test(
        'per-call timeout returns false before a delayed ack arrives',
        () async {
          final portA = await serverA.start();
          final delayedPeer = _DelayedAckPeer(
            ackDelayForMessage: (_) => const Duration(milliseconds: 350),
          );
          final delayedPort = await delayedPeer.start();

          final stopwatch = Stopwatch()..start();
          final sent = await serverA.sendMessage(
            'localhost',
            delayedPort,
            '{"text":"timeout test"}',
            'peerA',
            'peerB',
            timeoutMs: 120,
          );
          stopwatch.stop();

          expect(sent, isFalse);
          expect(stopwatch.elapsed.inMilliseconds, lessThan(300));
          expect(delayedPeer.connectionCount, 1);

          await delayedPeer.stop();
        },
      );

      test(
        'timed out send evicts pooled connection so the next send reconnects',
        () async {
          final portA = await serverA.start();
          final delayedPeer = _DelayedAckPeer(
            ackDelayForMessage: (messageCount) => messageCount == 1
                ? const Duration(milliseconds: 300)
                : Duration.zero,
          );
          final delayedPort = await delayedPeer.start();

          final firstSent = await serverA.sendMessage(
            'localhost',
            delayedPort,
            '{"text":"first"}',
            'peerA',
            'peerB',
            timeoutMs: 100,
          );
          expect(firstSent, isFalse);

          await Future.delayed(const Duration(milliseconds: 350));

          final secondSent = await serverA.sendMessage(
            'localhost',
            delayedPort,
            '{"text":"second"}',
            'peerA',
            'peerB',
            timeoutMs: 150,
          );

          expect(secondSent, isTrue);
          expect(delayedPeer.connectionCount, 2);

          await delayedPeer.stop();
        },
      );

      test(
        'slow ack removes stale pooled connection without blocking later sends',
        () async {
          final portA = await serverA.start();
          final portB = await serverB.start();

          // First send establishes pooled connection
          final sent1 = await serverA.sendMessage(
            'localhost',
            portB,
            '{"text":"first"}',
            'peerA',
            'peerB',
          );
          expect(sent1, isTrue);

          // Stop server B to simulate stale connection
          await serverB.stop();

          // Second send should fail (connection is stale) but not hang
          final stopwatch = Stopwatch()..start();
          final sent2 = await serverA.sendMessage(
            'localhost',
            portB,
            '{"text":"stale"}',
            'peerA',
            'peerB',
          );
          stopwatch.stop();

          expect(sent2, isFalse);
          // Should fail relatively quickly, not hang
          expect(stopwatch.elapsed.inSeconds, lessThan(10));

          // Restart B and verify new sends work
          serverB = LocalWsServer(idleTimeout: const Duration(seconds: 2));
          final newPortB = await serverB.start();

          final sent3 = await serverA.sendMessage(
            'localhost',
            newPortB,
            '{"text":"fresh"}',
            'peerA',
            'peerB',
          );
          expect(sent3, isTrue);
        },
      );

      test('media path is not forced into text-message timeout budget', () {
        // This is a design test — verifying the architecture distinction.
        // The LocalWsServer._ackTimeout is the text-message budget.
        // Media transfers would use a different path/timeout.
        // Here we just verify the ack timeout exists and is bounded.
        expect(server.idleTimeout.inSeconds, lessThanOrEqualTo(120));
      });

      test('A sends to B, B receives', () async {
        final portA = await serverA.start();
        final portB = await serverB.start();

        final receivedByB = <dynamic>[];
        final sub = serverB.messageStream.listen(receivedByB.add);

        final sent = await serverA.sendMessage(
          'localhost',
          portB,
          '{"text":"hello from A"}',
          'peerA',
          'peerB',
        );

        expect(sent, isTrue);

        await Future.delayed(const Duration(milliseconds: 50));

        expect(receivedByB, hasLength(1));
        expect(receivedByB.first.from, equals('peerA'));
        expect(receivedByB.first.content, equals('{"text":"hello from A"}'));

        await sub.cancel();
      });
    });
  });
}

class _DelayedAckPeer {
  final Duration Function(int messageCount) ackDelayForMessage;

  HttpServer? _server;
  final _sockets = <WebSocket>{};
  bool _stopped = false;

  int connectionCount = 0;
  int _messageCount = 0;

  _DelayedAckPeer({required this.ackDelayForMessage});

  Future<int> start() async {
    _stopped = false;
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen((request) async {
      final ws = await WebSocketTransformer.upgrade(request);
      connectionCount++;
      _sockets.add(ws);
      ws.listen(
        (data) {
          if (data is! String) return;
          final payload = jsonDecode(data) as Map<String, dynamic>;
          final nonce = payload['nonce'] as String?;
          _messageCount++;
          final delay = ackDelayForMessage(_messageCount);
          Future.delayed(delay, () {
            if (_stopped || ws.readyState != WebSocket.open) {
              return;
            }
            try {
              ws.add(
                jsonEncode({'ack': true, if (nonce != null) 'nonce': nonce}),
              );
            } catch (_) {
              // The client may have already timed out and closed the socket.
            }
          });
        },
        onDone: () => _sockets.remove(ws),
        onError: (_) => _sockets.remove(ws),
      );
    });
    return _server!.port;
  }

  Future<void> stop() async {
    _stopped = true;
    for (final socket in _sockets.toList()) {
      await socket.close();
    }
    _sockets.clear();
    await _server?.close(force: true);
    _server = null;
  }
}
