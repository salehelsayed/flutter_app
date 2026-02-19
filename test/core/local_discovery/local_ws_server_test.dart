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
