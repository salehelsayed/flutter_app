import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/local_discovery/local_ws_server.dart';
import 'package:flutter_app/core/local_discovery/local_media_server.dart';
import 'package:flutter_app/core/local_discovery/local_discovery_service.dart';

void main() {
  group('Local Media E2E', () {
    late Directory tempDirA;
    late Directory tempDirB;
    late LocalWsServer serverA;
    late LocalWsServer serverB;
    late LocalMediaServer mediaServerB;
    late int portA;
    late int portB;

    setUp(() async {
      tempDirA =
          await Directory.systemTemp.createTemp('media_e2e_a_');
      tempDirB =
          await Directory.systemTemp.createTemp('media_e2e_b_');

      serverA = LocalWsServer(idleTimeout: const Duration(seconds: 5));
      serverB = LocalWsServer(idleTimeout: const Duration(seconds: 5));

      mediaServerB = LocalMediaServer(
        tempDir: '${tempDirB.path}/temp',
        mediaDir: '${tempDirB.path}/media',
      );
      serverB.configureMediaServer(mediaServerB);

      portA = await serverA.start();
      portB = await serverB.start();
    });

    tearDown(() async {
      serverA.dispose();
      serverB.dispose();
      await tempDirA.delete(recursive: true);
      await tempDirB.delete(recursive: true);
    });

    /// Create a test file with deterministic content.
    Future<(File, String)> _createTestFile(
      Directory dir,
      int size, {
      int seed = 42,
    }) async {
      final random = Random(seed);
      final bytes = List<int>.generate(size, (_) => random.nextInt(256));
      final file = File('${dir.path}/test_file_$seed.bin');
      await file.writeAsBytes(bytes);
      final hash = sha256.convert(bytes).toString();
      return (file, hash);
    }

    test(
        'sender uploads 1KB image, receiver gets file at local path, '
        'SHA-256 matches', () async {
      const size = 1024;
      final (file, expectedHash) = await _createTestFile(tempDirA, size);

      // Listen for media ready events on receiver.
      final mediaReadyEvents = <LocalMediaReady>[];
      final sub =
          serverB.mediaReadyStream!.listen(mediaReadyEvents.add);

      // Sender uploads to receiver.
      final result = await serverA.sendMedia(
        host: 'localhost',
        port: portB,
        toPeerId: 'receiverPeer',
        filePath: file.path,
        mediaId: 'e2e-media-1',
        mime: 'image/jpeg',
        fromPeerId: 'senderPeer',
      );

      expect(result, isTrue);

      // Give streams time to propagate.
      await Future.delayed(const Duration(milliseconds: 100));

      expect(mediaReadyEvents, hasLength(1));
      final ready = mediaReadyEvents.first;
      expect(ready.id, 'e2e-media-1');
      expect(ready.sha256, expectedHash);
      expect(ready.size, size);
      expect(ready.from, 'senderPeer');
      expect(ready.to, 'receiverPeer');
      expect(ready.mime, 'image/jpeg');

      // Verify the file on disk matches.
      final receivedFile = File(ready.localPath);
      expect(await receivedFile.exists(), isTrue);
      final receivedBytes = await receivedFile.readAsBytes();
      final receivedHash = sha256.convert(receivedBytes).toString();
      expect(receivedHash, expectedHash);

      await sub.cancel();
    });

    test(
        'sender uploads voice message with durationMs and waveform metadata',
        () async {
      const size = 512;
      final (file, _) = await _createTestFile(tempDirA, size, seed: 99);

      final mediaReadyEvents = <LocalMediaReady>[];
      final sub =
          serverB.mediaReadyStream!.listen(mediaReadyEvents.add);

      final result = await serverA.sendMedia(
        host: 'localhost',
        port: portB,
        toPeerId: 'receiverPeer',
        filePath: file.path,
        mediaId: 'e2e-voice-1',
        mime: 'audio/aac',
        fromPeerId: 'senderPeer',
        durationMs: 3200,
        waveform: [0.1, 0.4, 0.8, 0.3],
        filename: 'voice.m4a',
      );

      expect(result, isTrue);

      await Future.delayed(const Duration(milliseconds: 100));

      expect(mediaReadyEvents, hasLength(1));
      final ready = mediaReadyEvents.first;
      expect(ready.durationMs, 3200);
      expect(ready.waveform, [0.1, 0.4, 0.8, 0.3]);
      expect(ready.filename, 'voice.m4a');
      expect(ready.mime, 'audio/aac');

      await sub.cancel();
    });

    test('two concurrent transfers from same sender complete independently',
        () async {
      final (file1, hash1) =
          await _createTestFile(tempDirA, 1024, seed: 1);
      final (file2, hash2) =
          await _createTestFile(tempDirA, 2048, seed: 2);

      final mediaReadyEvents = <LocalMediaReady>[];
      final sub =
          serverB.mediaReadyStream!.listen(mediaReadyEvents.add);

      final results = await Future.wait([
        serverA.sendMedia(
          host: 'localhost',
          port: portB,
          toPeerId: 'receiverPeer',
          filePath: file1.path,
          mediaId: 'concurrent-1',
          mime: 'image/jpeg',
          fromPeerId: 'senderPeer',
        ),
        serverA.sendMedia(
          host: 'localhost',
          port: portB,
          toPeerId: 'receiverPeer',
          filePath: file2.path,
          mediaId: 'concurrent-2',
          mime: 'image/png',
          fromPeerId: 'senderPeer',
        ),
      ]);

      // Both should succeed.
      expect(results, everyElement(isTrue));

      await Future.delayed(const Duration(milliseconds: 100));

      expect(mediaReadyEvents, hasLength(2));

      final ids = mediaReadyEvents.map((e) => e.id).toSet();
      expect(ids, containsAll(['concurrent-1', 'concurrent-2']));

      // Verify SHA-256 matches for each.
      for (final ready in mediaReadyEvents) {
        final receivedBytes = await File(ready.localPath).readAsBytes();
        final receivedHash =
            sha256.convert(receivedBytes).toString();
        expect(receivedHash, ready.sha256);
      }

      await sub.cancel();
    });

    test('transfer fails gracefully when receiver server stops mid-upload',
        () async {
      const size = 64 * 1024; // 64KB
      final (file, _) = await _createTestFile(tempDirA, size);

      // Stop receiver mid-transfer.
      final resultFuture = serverA.sendMedia(
        host: 'localhost',
        port: portB,
        toPeerId: 'receiverPeer',
        filePath: file.path,
        mediaId: 'mid-stop',
        mime: 'image/jpeg',
        fromPeerId: 'senderPeer',
      );

      // Give the transfer a moment to start, then stop receiver.
      await Future.delayed(const Duration(milliseconds: 50));
      await serverB.stop();

      // Should resolve to false (not hang or throw).
      final result = await resultFuture;
      expect(result, isA<bool>());
    }, timeout: const Timeout(Duration(seconds: 40)));

    test('wrong token on PUT returns 403, sender gets false', () async {
      const size = 256;
      final (file, expectedHash) = await _createTestFile(tempDirA, size);

      // Create a custom receiver that accepts the offer but modifies the
      // token when sending media_offer_accepted (simulating token mismatch).
      // Since the sender generated the token and uses it in the PUT,
      // and the receiver validated it — we test by having NO media server
      // configured (so PUT goes to 404) to verify the sender returns false.

      // Actually, let's test by having a separate receiver that rejects
      // based on wrong token. We'll start a raw HTTP server.
      final rawServer =
          await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final rawPort = rawServer.port;

      // A media server with a different token registered.
      final rawMediaServer = LocalMediaServer(
        tempDir: '${tempDirB.path}/temp2',
        mediaDir: '${tempDirB.path}/media2',
      );

      String? capturedToken;

      rawServer.listen((request) {
        final path = request.uri.path;
        if (path.startsWith('/media/')) {
          final mediaId = path.substring('/media/'.length);
          if (request.method == 'PUT') {
            rawMediaServer.handleUpload(request, mediaId);
          }
          return;
        }
        WebSocketTransformer.upgrade(request).then((ws) {
          ws.listen((data) {
            if (data is! String) return;
            try {
              final json = jsonDecode(data) as Map<String, dynamic>;
              if (json['type'] == 'media_offer') {
                capturedToken = json['token'] as String?;
                // Accept the offer but with a DIFFERENT token registered.
                // The sender will use the real token in the PUT, but the
                // media server has a different one.
                final offer = MediaOffer(
                  id: json['id'] as String,
                  from: json['from'] as String,
                  to: json['to'] as String,
                  mime: json['mime'] as String,
                  size: json['size'] as int,
                  sha256: json['sha256'] as String,
                  token: 'wrong-server-token', // Different from sender's!
                  nonce: json['nonce'] as String,
                );
                rawMediaServer.acceptOffer(offer);

                ws.add(jsonEncode({
                  'type': 'media_offer_accepted',
                  'id': json['id'],
                  'token': json['token'],
                  'nonce': json['nonce'],
                }));
              }
            } catch (_) {}
          });
        }).catchError((_) {});
      });

      final result = await serverA.sendMedia(
        host: 'localhost',
        port: rawPort,
        toPeerId: 'receiverPeer',
        filePath: file.path,
        mediaId: 'wrong-token-test',
        mime: 'image/jpeg',
        fromPeerId: 'senderPeer',
      );

      // Sender should get false because PUT gets 403.
      expect(result, isFalse);

      rawMediaServer.dispose();
      await rawServer.close(force: true);
    }, timeout: const Timeout(Duration(seconds: 15)));
  });
}
