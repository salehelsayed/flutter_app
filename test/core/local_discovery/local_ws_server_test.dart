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
      ws.add(jsonEncode({
        'from': 'peerA',
        'to': 'peerB',
        'content': '{"type":"chat","version":"1","payload":{"text":"hello"}}',
      }));

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

    group('nonce integrity', () {
      Future<(HttpServer, int)> _startCustomAckServer(
        void Function(WebSocket ws, Map<String, dynamic> json) onMessage,
      ) async {
        final httpServer =
            await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        httpServer.listen((request) {
          WebSocketTransformer.upgrade(request).then((ws) {
            ws.listen((data) {
              if (data is String) {
                try {
                  final json = jsonDecode(data) as Map<String, dynamic>;
                  onMessage(ws, json);
                } catch (_) {}
              }
            });
          }).catchError((_) {});
        });
        return (httpServer, httpServer.port);
      }

      test('sendMessage times out when ack has wrong nonce', () async {
        await server.start();

        final (remoteHttp, remotePort) = await _startCustomAckServer(
          (ws, json) {
            ws.add(jsonEncode({'ack': true, 'nonce': 'wrong-nonce'}));
          },
        );

        final sent = await server.sendMessage(
          'localhost',
          remotePort,
          '{"type":"chat","version":"1","payload":{"text":"hi"}}',
          'peerA',
          'peerB',
        );

        expect(sent, isFalse);

        await remoteHttp.close(force: true);
      }, timeout: const Timeout(Duration(seconds: 10)));

      test('sendMessage times out when ack has no nonce', () async {
        await server.start();

        final (remoteHttp, remotePort) = await _startCustomAckServer(
          (ws, json) {
            ws.add(jsonEncode({'ack': true}));
          },
        );

        final sent = await server.sendMessage(
          'localhost',
          remotePort,
          '{"type":"chat","version":"1","payload":{"text":"hi"}}',
          'peerA',
          'peerB',
        );

        expect(sent, isFalse);

        await remoteHttp.close(force: true);
      }, timeout: const Timeout(Duration(seconds: 10)));

      test('sendMessage succeeds when ack echoes correct nonce', () async {
        await server.start();

        final (remoteHttp, remotePort) = await _startCustomAckServer(
          (ws, json) {
            ws.add(jsonEncode({'ack': true, 'nonce': json['nonce']}));
          },
        );

        final sent = await server.sendMessage(
          'localhost',
          remotePort,
          '{"type":"chat","version":"1","payload":{"text":"hi"}}',
          'peerA',
          'peerB',
        );

        expect(sent, isTrue);

        await remoteHttp.close(force: true);
      });

      test('concurrent sends each resolve only their own nonce', () async {
        await server.start();

        final receivedNonces = <String>[];

        final (remoteHttp, remotePort) = await _startCustomAckServer(
          (ws, json) {
            final nonce = json['nonce'] as String;
            receivedNonces.add(nonce);
            // Delay the first response so both messages arrive before any ack
            if (receivedNonces.length == 1) {
              Future.delayed(const Duration(milliseconds: 200), () {
                ws.add(jsonEncode({'ack': true, 'nonce': nonce}));
              });
            } else {
              ws.add(jsonEncode({'ack': true, 'nonce': nonce}));
            }
          },
        );

        // Use different toPeerIds so each send creates its own connection
        // (the pool keys on toPeerId). Actually, let's use the same peer
        // to exercise concurrent sends on the same pooled connection.
        final results = await Future.wait([
          server.sendMessage(
            'localhost',
            remotePort,
            '{"type":"chat","version":"1","payload":{"text":"msg1"}}',
            'peerA',
            'peerB',
          ),
          server.sendMessage(
            'localhost',
            remotePort,
            '{"type":"chat","version":"1","payload":{"text":"msg2"}}',
            'peerA',
            'peerB',
          ),
        ]);

        expect(results, everyElement(isTrue));
        expect(receivedNonces, hasLength(2));
        expect(receivedNonces[0], isNot(equals(receivedNonces[1])));

        await remoteHttp.close(force: true);
      });

      test(
          'concurrent sends do not cross-ack when acks arrive in swapped order',
          () async {
        await server.start();

        final collected = <(WebSocket, String)>[];
        final allReceived = Completer<void>();

        final (remoteHttp, remotePort) = await _startCustomAckServer(
          (ws, json) {
            final nonce = json['nonce'] as String;
            collected.add((ws, nonce));
            if (collected.length == 2 && !allReceived.isCompleted) {
              // Ack in reverse order
              final (ws2, nonce2) = collected[1];
              final (ws1, nonce1) = collected[0];
              ws2.add(jsonEncode({'ack': true, 'nonce': nonce2}));
              ws1.add(jsonEncode({'ack': true, 'nonce': nonce1}));
              allReceived.complete();
            }
          },
        );

        final results = await Future.wait([
          server.sendMessage(
            'localhost',
            remotePort,
            '{"type":"chat","version":"1","payload":{"text":"msg1"}}',
            'peerA',
            'peerB',
          ),
          server.sendMessage(
            'localhost',
            remotePort,
            '{"type":"chat","version":"1","payload":{"text":"msg2"}}',
            'peerA',
            'peerB',
          ),
        ]);

        expect(results, everyElement(isTrue));

        await remoteHttp.close(force: true);
      });

      test('wrong nonce ack does not satisfy any pending send', () async {
        await server.start();

        final (remoteHttp, remotePort) = await _startCustomAckServer(
          (ws, json) {
            // Always reply with a fabricated nonce — never the real one
            ws.add(jsonEncode({'ack': true, 'nonce': 'fabricated-nonce'}));
          },
        );

        final results = await Future.wait([
          server.sendMessage(
            'localhost',
            remotePort,
            '{"type":"chat","version":"1","payload":{"text":"msg1"}}',
            'peerA',
            'peerB',
          ),
          server.sendMessage(
            'localhost',
            remotePort,
            '{"type":"chat","version":"1","payload":{"text":"msg2"}}',
            'peerA',
            'peerB',
          ),
        ]);

        expect(results, everyElement(isFalse));

        await remoteHttp.close(force: true);
      }, timeout: const Timeout(Duration(seconds: 15)));
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
