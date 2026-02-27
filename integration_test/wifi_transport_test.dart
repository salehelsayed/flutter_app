// WiFi Transport Integration Tests
//
// Tests the LocalWsServer WebSocket messaging directly, without mDNS.
// Two LocalWsServer instances communicate via localhost, verifying:
//   F1: WiFi send/receive
//   F2: WiFi ack timeout
//   F3: WiFi connection pool reuse
//   F4: WiFi idle disconnect
//
// Launch:
//   flutter test integration_test/wifi_transport_test.dart -d <device>

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_app/core/local_discovery/local_ws_server.dart';
import 'package:flutter_app/core/local_discovery/local_media_server.dart';
import 'package:flutter_app/core/local_discovery/local_discovery_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const peerA = 'peer-a-test-id';
  const peerB = 'peer-b-test-id';

  // =========================================================================
  // F1: WiFi send/receive
  // =========================================================================

  testWidgets('F1: WiFi send/receive via WebSocket', (tester) async {
    print('\n========================================');
    print('F1: WiFi send/receive');
    print('========================================\n');

    final serverA = LocalWsServer();
    final serverB = LocalWsServer();

    try {
      // Start both servers.
      final portA = await serverA.start();
      final portB = await serverB.start();
      print('[TEST] Server A on port $portA, Server B on port $portB');

      // Collect messages received by server B.
      final receivedByB = <LocalChatMessage>[];
      final sub = serverB.messageStream.listen(receivedByB.add);

      // A sends message to B.
      final sent = await serverA.sendMessage(
        'localhost',
        portB,
        'Hello from A to B via WiFi',
        peerA,
        peerB,
      );

      expect(sent, isTrue, reason: 'Send should succeed');

      // Wait for message to arrive.
      await Future.delayed(const Duration(milliseconds: 500));

      expect(receivedByB.length, 1, reason: 'B should receive 1 message');
      expect(receivedByB.first.from, peerA);
      expect(receivedByB.first.to, peerB);
      expect(receivedByB.first.content, 'Hello from A to B via WiFi');
      expect(receivedByB.first.isIncoming, isTrue);

      print('[TEST] F1 PASS: message received correctly');

      await sub.cancel();
    } finally {
      serverA.dispose();
      serverB.dispose();
    }
  });

  // =========================================================================
  // F2: WiFi ack timeout
  // =========================================================================

  testWidgets('F2: WiFi ack timeout returns false', (tester) async {
    print('\n========================================');
    print('F2: WiFi ack timeout');
    print('========================================\n');

    final serverA = LocalWsServer();

    try {
      await serverA.start();

      // Start a raw HttpServer that accepts WebSocket but never sends ack.
      final silentServer = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      final silentPort = silentServer.port;
      print('[TEST] Silent server on port $silentPort');

      silentServer.listen((request) {
        WebSocketTransformer.upgrade(request)
            .then((ws) {
              // Accept messages but never reply — no ack.
              ws.listen((_) {});
            })
            .catchError((_) {});
      });

      // A sends to the silent server — should timeout after 5 seconds.
      final stopwatch = Stopwatch()..start();
      final sent = await serverA.sendMessage(
        'localhost',
        silentPort,
        'This will not be acked',
        peerA,
        peerB,
      );
      stopwatch.stop();

      expect(sent, isFalse, reason: 'Send should fail due to ack timeout');
      expect(
        stopwatch.elapsedMilliseconds,
        greaterThan(4000),
        reason: 'Should wait ~5s for ack timeout',
      );
      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(10000),
        reason: 'Should not wait much longer than 5s',
      );

      print(
        '[TEST] F2 PASS: ack timeout after ${stopwatch.elapsedMilliseconds}ms',
      );

      await silentServer.close();
    } finally {
      serverA.dispose();
    }
  });

  // =========================================================================
  // F3: WiFi connection pool reuse
  // =========================================================================

  testWidgets('F3: WiFi connection pool reuse across sequential sends', (
    tester,
  ) async {
    print('\n========================================');
    print('F3: WiFi connection pool reuse');
    print('========================================\n');

    final serverA = LocalWsServer();
    final serverB = LocalWsServer();

    try {
      await serverA.start();
      final portB = await serverB.start();
      print('[TEST] Server B on port $portB');

      final receivedByB = <LocalChatMessage>[];
      final sub = serverB.messageStream.listen(receivedByB.add);

      // Send 3 messages sequentially. The pooled connection's broadcast
      // stream allows multiple ack waits on the same WebSocket.
      for (var i = 1; i <= 3; i++) {
        final sent = await serverA.sendMessage(
          'localhost',
          portB,
          'Message $i',
          peerA,
          peerB,
        );
        expect(sent, isTrue, reason: 'Send $i should succeed via pool reuse');
        // Small delay between sends.
        await Future.delayed(const Duration(milliseconds: 100));
      }

      await Future.delayed(const Duration(milliseconds: 500));

      // All 3 sends should succeed and all 3 messages should be received.
      expect(receivedByB.length, 3, reason: 'B should receive all 3 messages');
      expect(receivedByB[0].content, 'Message 1');
      expect(receivedByB[1].content, 'Message 2');
      expect(receivedByB[2].content, 'Message 3');

      print(
        '[TEST] F3 PASS: all 3 sends succeeded via pool reuse, '
        '${receivedByB.length} messages received',
      );

      await sub.cancel();
    } finally {
      serverA.dispose();
      serverB.dispose();
    }
  });

  // =========================================================================
  // F4: WiFi idle disconnect
  // =========================================================================

  testWidgets('F4: WiFi idle disconnect after timeout', (tester) async {
    print('\n========================================');
    print('F4: WiFi idle disconnect');
    print('========================================\n');

    // Use a very short idle timeout for testing.
    final serverA = LocalWsServer(idleTimeout: const Duration(seconds: 2));
    final serverB = LocalWsServer();

    try {
      await serverA.start();
      final portB = await serverB.start();

      final receivedByB = <LocalChatMessage>[];
      final sub = serverB.messageStream.listen(receivedByB.add);

      // Send a message to establish the pooled connection.
      final sent1 = await serverA.sendMessage(
        'localhost',
        portB,
        'Before idle timeout',
        peerA,
        peerB,
      );
      expect(sent1, isTrue);

      await Future.delayed(const Duration(milliseconds: 500));
      expect(receivedByB.length, 1);
      print('[TEST] F4: First message sent successfully');

      // Wait for idle timeout to fire (2 seconds + buffer).
      print('[TEST] F4: Waiting for idle timeout (2s)...');
      await Future.delayed(const Duration(seconds: 3));

      // The pooled connection should now be closed.
      // Sending again should create a new connection.
      final sent2 = await serverA.sendMessage(
        'localhost',
        portB,
        'After idle timeout (new connection)',
        peerA,
        peerB,
      );
      expect(sent2, isTrue);

      await Future.delayed(const Duration(milliseconds: 500));
      expect(receivedByB.length, 2);

      print(
        '[TEST] F4 PASS: idle disconnect worked, '
        'reconnected and sent second message',
      );

      await sub.cancel();
    } finally {
      serverA.dispose();
      serverB.dispose();
    }
  });

  // =========================================================================
  // F5: Bidirectional WiFi communication
  // =========================================================================

  testWidgets('F5: Bidirectional WiFi messages', (tester) async {
    print('\n========================================');
    print('F5: Bidirectional WiFi messages');
    print('========================================\n');

    final serverA = LocalWsServer();
    final serverB = LocalWsServer();

    try {
      final portA = await serverA.start();
      final portB = await serverB.start();

      final receivedByA = <LocalChatMessage>[];
      final receivedByB = <LocalChatMessage>[];
      final subA = serverA.messageStream.listen(receivedByA.add);
      final subB = serverB.messageStream.listen(receivedByB.add);

      // A → B
      final sent1 = await serverA.sendMessage(
        'localhost',
        portB,
        'A to B',
        peerA,
        peerB,
      );
      expect(sent1, isTrue);

      // B → A
      final sent2 = await serverB.sendMessage(
        'localhost',
        portA,
        'B to A',
        peerB,
        peerA,
      );
      expect(sent2, isTrue);

      await Future.delayed(const Duration(milliseconds: 500));

      expect(receivedByB.length, 1);
      expect(receivedByB.first.content, 'A to B');
      expect(receivedByA.length, 1);
      expect(receivedByA.first.content, 'B to A');

      print('[TEST] F5 PASS: bidirectional communication works');

      await subA.cancel();
      await subB.cancel();
    } finally {
      serverA.dispose();
      serverB.dispose();
    }
  });

  // =========================================================================
  // F6: Malformed WebSocket messages silently ignored
  // =========================================================================

  testWidgets('F6: Malformed messages silently ignored', (tester) async {
    print('\n========================================');
    print('F6: Malformed messages');
    print('========================================\n');

    final server = LocalWsServer();

    try {
      final port = await server.start();

      final received = <LocalChatMessage>[];
      final sub = server.messageStream.listen(received.add);

      // Connect directly and send garbage.
      final ws = await WebSocket.connect('ws://localhost:$port');
      ws.add('not valid json');
      ws.add('{"partial": true}'); // Missing from/to/content.
      ws.add(
        jsonEncode({
          'from': peerA,
          'to': peerB,
          'content': 'Valid message after garbage',
        }),
      );

      await Future.delayed(const Duration(milliseconds: 500));

      // Only the valid message should be received.
      expect(received.length, 1);
      expect(received.first.content, 'Valid message after garbage');

      print(
        '[TEST] F6 PASS: malformed messages ignored, '
        'valid message received',
      );

      await ws.close();
      await sub.cancel();
    } finally {
      server.dispose();
    }
  });

  // =========================================================================
  // F7: Concurrent WiFi sends on same pooled connection
  // =========================================================================

  testWidgets('F7: Concurrent WiFi sends via Future.wait', (tester) async {
    print('\n========================================');
    print('F7: Concurrent WiFi sends');
    print('========================================\n');

    final serverA = LocalWsServer();
    final serverB = LocalWsServer();

    try {
      await serverA.start();
      final portB = await serverB.start();
      print('[TEST] Server B on port $portB');

      final receivedByB = <LocalChatMessage>[];
      final sub = serverB.messageStream.listen(receivedByB.add);

      // Fire two sends concurrently on the same pooled connection.
      // Per-message ack correlation via nonce: each send includes a unique nonce,
      // the server echoes it back, and each waiter matches only its own nonce.
      // Both sends resolve on their own acks, proving correct correlation.
      final results = await Future.wait([
        serverA.sendMessage(
          'localhost',
          portB,
          'Concurrent msg 1',
          peerA,
          peerB,
        ),
        serverA.sendMessage(
          'localhost',
          portB,
          'Concurrent msg 2',
          peerA,
          peerB,
        ),
      ]);

      expect(
        results[0],
        isTrue,
        reason: 'First concurrent send should succeed',
      );
      expect(
        results[1],
        isTrue,
        reason: 'Second concurrent send should succeed',
      );

      // Wait for messages to arrive.
      await Future.delayed(const Duration(milliseconds: 500));

      expect(
        receivedByB.length,
        2,
        reason: 'Server B should receive both concurrent messages',
      );
      final contents = receivedByB.map((m) => m.content).toSet();
      expect(contents, contains('Concurrent msg 1'));
      expect(contents, contains('Concurrent msg 2'));

      print(
        '[TEST] F7 PASS: both concurrent sends succeeded, '
        '${receivedByB.length} messages received',
      );

      await sub.cancel();
    } finally {
      serverA.dispose();
      serverB.dispose();
    }
  });

  // =========================================================================
  // F8: WiFi max connections rejection + recovery
  // =========================================================================

  testWidgets('F8: Max connections rejection and recovery', (tester) async {
    print('\n========================================');
    print('F8: Max connections rejection + recovery');
    print('========================================\n');

    final server = LocalWsServer();

    final rawConnections = <WebSocket>[];

    try {
      final port = await server.start();
      print('[TEST] Server on port $port');

      // Open 10 raw WebSocket connections (filling the max inbound limit).
      for (var i = 1; i <= 10; i++) {
        final ws = await WebSocket.connect('ws://localhost:$port');
        rawConnections.add(ws);
      }
      print('[TEST] F8: Opened 10 connections (at max)');

      // 11th connection should be rejected with HTTP 503.
      var rejected = false;
      try {
        final ws11 = await WebSocket.connect('ws://localhost:$port');
        // If we get here, the server didn't reject — close it and fail.
        await ws11.close();
      } on WebSocketException {
        rejected = true;
      } on HttpException {
        rejected = true;
      } catch (e) {
        // Other connection errors also indicate rejection.
        rejected = true;
        print('[TEST] F8: 11th connection error: $e');
      }

      expect(
        rejected,
        isTrue,
        reason: '11th connection should be rejected (max 10)',
      );
      print('[TEST] F8: 11th connection correctly rejected');

      // Close one connection to free a slot.
      await rawConnections.removeLast().close();
      print('[TEST] F8: Closed one connection, freeing a slot');

      // Small delay for server to process the close.
      await Future.delayed(const Duration(milliseconds: 200));

      // New connection should succeed.
      final recovered = await WebSocket.connect('ws://localhost:$port');
      rawConnections.add(recovered);
      print('[TEST] F8: Recovery connection succeeded');

      // Verify a message works through the recovered slot.
      final received = <LocalChatMessage>[];
      final sub = server.messageStream.listen(received.add);

      recovered.add(
        jsonEncode({
          'from': peerA,
          'to': peerB,
          'content': 'F8: Recovery message',
        }),
      );

      await Future.delayed(const Duration(milliseconds: 500));

      expect(received.length, 1, reason: 'Should receive recovery message');
      expect(received.first.content, 'F8: Recovery message');

      print('[TEST] F8 PASS: rejection at max, recovery after close');

      await sub.cancel();
    } finally {
      for (final ws in rawConnections) {
        await ws.close().catchError((_) {});
      }
      server.dispose();
    }
  });

  // =========================================================================
  // F9: WiFi remote close + graceful failure
  // =========================================================================

  testWidgets('F9: Remote close and graceful failure', (tester) async {
    print('\n========================================');
    print('F9: Remote close + graceful failure');
    print('========================================\n');

    final serverA = LocalWsServer();
    var serverB = LocalWsServer();

    try {
      await serverA.start();
      final portB = await serverB.start();
      print('[TEST] Server B on port $portB');

      // Step 1: A sends to B successfully (creates pooled connection).
      final receivedByB = <LocalChatMessage>[];
      var subB = serverB.messageStream.listen(receivedByB.add);

      final sent1 = await serverA.sendMessage(
        'localhost',
        portB,
        'F9: Before remote close',
        peerA,
        peerB,
      );
      expect(sent1, isTrue, reason: 'First send should succeed');
      await Future.delayed(const Duration(milliseconds: 500));
      expect(receivedByB.length, 1);
      print('[TEST] F9: First send succeeded');

      await subB.cancel();

      // Step 2: Stop server B (remote close).
      await serverB.stop();
      print('[TEST] F9: Server B stopped');

      // Step 3: Wait for close propagation (pool's onDone fires _removeFromPool).
      await Future.delayed(const Duration(seconds: 1));

      // Step 4: A sends to B on same port — should fail (connection dead).
      final sent2 = await serverA.sendMessage(
        'localhost',
        portB,
        'F9: This should fail',
        peerA,
        peerB,
      );
      expect(sent2, isFalse, reason: 'Send to stopped server should fail');
      print('[TEST] F9: Send to stopped server correctly failed');

      // Step 5: Restart B as a new server on a new port.
      serverB = LocalWsServer();
      final newPortB = await serverB.start();
      print('[TEST] F9: New server B on port $newPortB');

      final receivedByNewB = <LocalChatMessage>[];
      subB = serverB.messageStream.listen(receivedByNewB.add);

      // Step 6: A sends to B's new port with same peer ID.
      // The pool was keyed by peerB — the stale entry was evicted in step 4's
      // failure (triggers _removeFromPool), so step 6 creates a fresh connection.
      final sent3 = await serverA.sendMessage(
        'localhost',
        newPortB,
        'F9: After restart',
        peerA,
        peerB,
      );
      expect(sent3, isTrue, reason: 'Send to restarted server should succeed');

      await Future.delayed(const Duration(milliseconds: 500));

      // Step 7: Verify message received by restarted server.
      expect(receivedByNewB.length, 1);
      expect(receivedByNewB.first.content, 'F9: After restart');

      print('[TEST] F9 PASS: remote close handled gracefully, reconnected');

      await subB.cancel();
    } finally {
      serverA.dispose();
      serverB.dispose();
    }
  });

  // =========================================================================
  // F10: WiFi media transfer
  // =========================================================================

  testWidgets('F10: WiFi media transfer via HTTP PUT + WS signaling', (
    tester,
  ) async {
    print('\n========================================');
    print('F10: WiFi media transfer');
    print('========================================\n');

    final tempA = await Directory.systemTemp.createTemp('wifi_media_a_');
    final tempB = await Directory.systemTemp.createTemp('wifi_media_b_');
    final serverA = LocalWsServer();
    final serverB = LocalWsServer();
    final mediaServerB = LocalMediaServer(
      tempDir: '${tempB.path}/temp',
      mediaDir: '${tempB.path}/media',
    );
    serverB.configureMediaServer(mediaServerB);

    try {
      final portA = await serverA.start();
      final portB = await serverB.start();
      print('[TEST] Server A on port $portA, Server B on port $portB');

      final bytes = List<int>.generate(4096, (i) => i % 256);
      final file = File('${tempA.path}/photo.jpg');
      await file.writeAsBytes(bytes);
      final expectedHash = sha256.convert(bytes).toString();

      final readyEvents = <LocalMediaReady>[];
      final sub = serverB.mediaReadyStream!.listen(readyEvents.add);

      final sent = await serverA.sendMedia(
        host: 'localhost',
        port: portB,
        toPeerId: peerB,
        filePath: file.path,
        mediaId: 'wifi-media-001',
        mime: 'image/jpeg',
        fromPeerId: peerA,
      );
      expect(sent, isTrue, reason: 'Media send should succeed');

      await Future.delayed(const Duration(milliseconds: 200));
      expect(readyEvents, hasLength(1));
      expect(readyEvents.first.id, 'wifi-media-001');
      expect(readyEvents.first.from, peerA);
      expect(readyEvents.first.to, peerB);
      expect(readyEvents.first.sha256, expectedHash);

      final receivedFile = File(readyEvents.first.localPath);
      expect(await receivedFile.exists(), isTrue);
      final receivedHash = sha256.convert(await receivedFile.readAsBytes());
      expect(receivedHash.toString(), expectedHash);
      print('[TEST] F10 PASS: media transferred and hash verified');

      await sub.cancel();
    } finally {
      serverA.dispose();
      serverB.dispose();
      await tempA.delete(recursive: true);
      await tempB.delete(recursive: true);
    }
  });
}
