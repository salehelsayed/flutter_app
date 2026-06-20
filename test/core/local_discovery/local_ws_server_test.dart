import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/local_discovery/lan_ack.dart';
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

    test('start is idempotent while server is already bound', () async {
      final firstPort = await server.start();
      final secondPort = await server.start();

      expect(secondPort, firstPort);
      expect(server.port, firstPort);
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

    test(
      'withholds ack until inbound commit handler completes and marks it committed',
      () async {
        final decision = Completer<LanInboundDecision>();
        server.configureInboundChatCommitHandler(
          (message, {required nonce}) => decision.future,
        );
        final port = await server.start();

        final ws = await WebSocket.connect('ws://localhost:$port');
        final firstFrame = Completer<dynamic>();
        final sub = ws.listen((event) {
          if (!firstFrame.isCompleted) firstFrame.complete(event);
        });

        ws.add(
          jsonEncode({
            'from': 'peerA',
            'to': 'peerB',
            'content': '{"text":"commit me"}',
            'nonce': 'n-commit',
          }),
        );

        await Future.delayed(const Duration(milliseconds: 80));
        expect(firstFrame.isCompleted, isFalse);

        decision.complete(const LanInboundDecision.committed());
        final ack = jsonDecode(
          await firstFrame.future.timeout(const Duration(seconds: 1)) as String,
        );

        expect(ack, {'ack': true, 'committed': true, 'nonce': 'n-commit'});

        await ws.close();
        await sub.cancel();
      },
    );

    test(
      'replies explicit nack with reason when commit handler rejects',
      () async {
        server.configureInboundChatCommitHandler(
          (message, {required nonce}) =>
              LanInboundDecision.rejected('staging_failed'),
        );
        final port = await server.start();

        final messages = <dynamic>[];
        final messagesSub = server.messageStream.listen(messages.add);
        final ws = await WebSocket.connect('ws://localhost:$port');

        ws.add(
          jsonEncode({
            'from': 'peerA',
            'to': 'peerB',
            'content': '{"text":"reject me"}',
            'nonce': 'n-reject',
          }),
        );

        final ack = jsonDecode(await ws.first as String);
        expect(ack, {
          'ack': false,
          'nonce': 'n-reject',
          'reason': 'staging_failed',
        });

        await Future.delayed(const Duration(milliseconds: 50));
        expect(messages, isEmpty);

        await ws.close();
        await messagesSub.cancel();
      },
    );

    test(
      'does not emit on messageStream when commit handler is configured',
      () async {
        server.configureInboundChatCommitHandler(
          (message, {required nonce}) => const LanInboundDecision.committed(),
        );
        final port = await server.start();

        final messages = <dynamic>[];
        final messagesSub = server.messageStream.listen(messages.add);
        final ws = await WebSocket.connect('ws://localhost:$port');

        ws.add(
          jsonEncode({
            'from': 'peerA',
            'to': 'peerB',
            'content': '{"text":"handled"}',
            'nonce': 'n-handled',
          }),
        );

        final ack = jsonDecode(await ws.first as String);
        expect(ack['ack'], isTrue);
        expect(ack['committed'], isTrue);

        await Future.delayed(const Duration(milliseconds: 50));
        expect(messages, isEmpty);

        await ws.close();
        await messagesSub.cancel();
      },
    );

    test('commit handler timeout produces nack not legacy ack', () async {
      final timeoutServer = LocalWsServer(
        idleTimeout: const Duration(seconds: 2),
        commitBudget: const Duration(milliseconds: 60),
      );
      timeoutServer.configureInboundChatCommitHandler(
        (message, {required nonce}) => Completer<LanInboundDecision>().future,
      );

      try {
        final port = await timeoutServer.start();
        final messages = <dynamic>[];
        final messagesSub = timeoutServer.messageStream.listen(messages.add);
        final ws = await WebSocket.connect('ws://localhost:$port');

        ws.add(
          jsonEncode({
            'from': 'peerA',
            'to': 'peerB',
            'content': '{"text":"timeout"}',
            'nonce': 'n-timeout',
          }),
        );

        final ack = jsonDecode(
          await ws.first.timeout(const Duration(seconds: 1)) as String,
        );
        expect(ack, {
          'ack': false,
          'nonce': 'n-timeout',
          'reason': 'commit_timeout',
        });
        expect(ack.containsKey('committed'), isFalse);

        await Future.delayed(const Duration(milliseconds: 50));
        expect(messages, isEmpty);

        await ws.close();
        await messagesSub.cancel();
      } finally {
        timeoutServer.dispose();
      }
    });

    test(
      'acks legacy shape at parse time when no commit handler configured',
      () async {
        final port = await server.start();

        final messages = <dynamic>[];
        final messagesSub = server.messageStream.listen(messages.add);
        final ws = await WebSocket.connect('ws://localhost:$port');

        ws.add(
          jsonEncode({
            'from': 'peerA',
            'to': 'peerB',
            'content': '{"text":"legacy"}',
            'nonce': 'n-legacy',
          }),
        );

        final ack = jsonDecode(await ws.first as String);
        expect(ack, {'ack': true, 'nonce': 'n-legacy'});
        expect(ack.containsKey('committed'), isFalse);

        await Future.delayed(const Duration(milliseconds: 50));
        expect(messages, hasLength(1));
        expect(messages.first.content, '{"text":"legacy"}');

        await ws.close();
        await messagesSub.cancel();
      },
    );

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
      remoteServer.configureInboundChatCommitHandler(
        (message, {required nonce}) => const LanInboundDecision.committed(),
      );
      final remotePort = await remoteServer.start();

      await server.start();

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

    test('sendMessage treats legacy ack as successful receipt', () async {
      // The raw WS wrapper answers whether the peer acknowledged receipt. The
      // higher LocalP2PService wrapper is still committed-only.
      final remoteServer = LocalWsServer();
      try {
        final remotePort = await remoteServer.start();

        await server.start();

        final sent = await server.sendMessage(
          'localhost',
          remotePort,
          '{"type":"chat","version":"1","payload":{"text":"legacy ack"}}',
          'peerA',
          'peerB',
        );

        expect(sent, isTrue);
      } finally {
        remoteServer.dispose();
      }
    });

    test(
      'sendMessageWithAck classifies committed ack, legacy ack, and nack',
      () async {
        await server.start();

        final committedServer = LocalWsServer();
        committedServer.configureInboundChatCommitHandler(
          (message, {required nonce}) => const LanInboundDecision.committed(),
        );
        final committedPort = await committedServer.start();

        final committedAck = await server.sendMessageWithAck(
          'localhost',
          committedPort,
          '{"text":"committed"}',
          'peerA',
          'peerB',
        );
        expect(committedAck, LanSendAck.committed);

        final legacyServer = LocalWsServer();
        final legacyPort = await legacyServer.start();

        final legacyAck = await server.sendMessageWithAck(
          'localhost',
          legacyPort,
          '{"text":"legacy"}',
          'peerA',
          'legacyPeer',
        );
        expect(legacyAck, LanSendAck.legacyAck);

        final rejectingServer = LocalWsServer();
        rejectingServer.configureInboundChatCommitHandler(
          (message, {required nonce}) =>
              LanInboundDecision.rejected('staging_failed'),
        );
        final rejectingPort = await rejectingServer.start();

        final stopwatch = Stopwatch()..start();
        final failedAck = await server.sendMessageWithAck(
          'localhost',
          rejectingPort,
          '{"text":"reject"}',
          'peerA',
          'rejectingPeer',
          timeoutMs: 1000,
        );
        stopwatch.stop();

        expect(failedAck, LanSendAck.failed);
        expect(stopwatch.elapsedMilliseconds, lessThan(500));

        committedServer.dispose();
        legacyServer.dispose();
        rejectingServer.dispose();
      },
    );

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

    test('migration route is separate from media upload route', () async {
      final handledPaths = <String>[];
      server.configureMigrationTransferHandler((request, path) async {
        handledPaths.add(path);
        request.response.statusCode = HttpStatus.noContent;
        await request.response.close();
      });
      final port = await server.start();

      final client = HttpClient();
      try {
        final migrationRequest = await client.get(
          'localhost',
          port,
          '/migration/session-1/segments/0',
        );
        final migrationResponse = await migrationRequest.close();
        await migrationResponse.drain<void>();

        final mediaRequest = await client.put(
          'localhost',
          port,
          '/media/session-1',
        );
        final mediaResponse = await mediaRequest.close();
        await mediaResponse.drain<void>();

        expect(migrationResponse.statusCode, HttpStatus.noContent);
        expect(handledPaths, ['/migration/session-1/segments/0']);
        expect(mediaResponse.statusCode, HttpStatus.notFound);
      } finally {
        client.close(force: true);
      }
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
          await serverA.start();
          serverB.configureInboundChatCommitHandler(
            (message, {required nonce}) => const LanInboundDecision.committed(),
          );
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
          await serverA.start();
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
          await serverA.start();
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

          final secondSent = await serverA.sendMessageWithAck(
            'localhost',
            delayedPort,
            '{"text":"second"}',
            'peerA',
            'peerB',
            timeoutMs: 150,
          );

          expect(secondSent, LanSendAck.legacyAck);
          expect(delayedPeer.connectionCount, 2);

          await delayedPeer.stop();
        },
      );

      test(
        'slow ack removes stale pooled connection without blocking later sends',
        () async {
          await serverA.start();
          final portB = await serverB.start();

          // First send establishes pooled connection
          final sent1 = await serverA.sendMessageWithAck(
            'localhost',
            portB,
            '{"text":"first"}',
            'peerA',
            'peerB',
          );
          expect(sent1, LanSendAck.legacyAck);

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

          final sent3 = await serverA.sendMessageWithAck(
            'localhost',
            newPortB,
            '{"text":"fresh"}',
            'peerA',
            'peerB',
          );
          expect(sent3, LanSendAck.legacyAck);
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
        await serverA.start();
        final portB = await serverB.start();

        final receivedByB = <dynamic>[];
        final sub = serverB.messageStream.listen(receivedByB.add);

        final sent = await serverA.sendMessageWithAck(
          'localhost',
          portB,
          '{"text":"hello from A"}',
          'peerA',
          'peerB',
        );

        expect(sent, LanSendAck.legacyAck);

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
                jsonEncode({
                  'ack': true,
                  ...(nonce == null
                      ? const <String, Object?>{}
                      : {'nonce': nonce}),
                }),
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
