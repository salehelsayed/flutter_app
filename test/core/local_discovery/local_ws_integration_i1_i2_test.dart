// LAN/WS integration coverage — host-runnable (real LocalWsServer over
// loopback, no mDNS, no device). Companion to the device-only
// integration_test/wifi_transport_test.dart, runnable under `flutter test`.
//
// Tracking: NET-REL-01 (01-lan-wifi-reliability.md), test plan items I1/I2.
//
//   I1 (happy): text send/ack + media transfer with SHA-256 verification,
//       including the PRODUCTION-WIRING media variant that drives the full
//       receive chain LocalMediaServer PUT -> mediaReadyStream -> persistMedia
//       (temp -> persistent media dir), mirroring lib/main.dart's
//       incomingLocalMediaStream consumer. wifi_transport_test.dart F10 and
//       local_media_integration_test.dart only assert the *temp* localPath;
//       this variant proves the file survives the move that protects it from
//       the 5-min pendingTtl GC, which is what production actually relies on.
//
//   I2 (unhappy): a silent server that never acks -> sendMessage returns false
//       within the ack timeout; a stale host:port -> connect fails fast inside
//       the LocalWsServer._connectTimeout (800ms) budget rather than burning
//       the full local send budget. Extends the F2/F8/F9 family.
//
// Real-mDNS device tests (I3) and the iOS Local-Network permission matrix
// remain device-only and out of host scope (BonsoirDiscoveryService is never
// instantiated in tests; sims share the host mDNS stack and disable discovery).

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/local_discovery/local_discovery_service.dart';
import 'package:flutter_app/core/local_discovery/local_media_server.dart';
import 'package:flutter_app/core/local_discovery/local_ws_server.dart';

void main() {
  const peerA = 'peer-a-test-id';
  const peerB = 'peer-b-test-id';

  // ==========================================================================
  // I1 — happy path
  // ==========================================================================

  group('I1 happy: text + media over loopback', () {
    test('text: A -> B delivers, B acks, content intact', () async {
      final serverA = LocalWsServer();
      final serverB = LocalWsServer();
      try {
        await serverA.start();
        final portB = await serverB.start();

        final received = <LocalChatMessage>[];
        final sub = serverB.messageStream.listen(received.add);

        // content is the already-built E2E envelope on the real send path; an
        // opaque string here is faithful to what the WS layer actually carries.
        const envelope = '{"version":"2","encrypted":{"kem":"k","ct":"c"}}';
        final sent = await serverA.sendMessage(
          'localhost',
          portB,
          envelope,
          peerA,
          peerB,
        );
        expect(sent, isTrue, reason: 'B should ack within budget');

        await Future.delayed(const Duration(milliseconds: 300));
        expect(received, hasLength(1));
        expect(received.first.from, peerA);
        expect(received.first.to, peerB);
        expect(received.first.content, envelope);
        expect(received.first.isIncoming, isTrue);

        await sub.cancel();
      } finally {
        serverA.dispose();
        serverB.dispose();
      }
    });

    test(
      'media production-wiring: PUT -> mediaReadyStream -> persistMedia '
      'lands a SHA-256-verified file in the persistent media dir',
      () async {
        final tempA = await Directory.systemTemp.createTemp('i1_media_a_');
        final tempB = await Directory.systemTemp.createTemp('i1_media_b_');
        final serverA = LocalWsServer();
        final serverB = LocalWsServer();
        final mediaServerB = LocalMediaServer(
          tempDir: '${tempB.path}/local_media_tmp',
          mediaDir: '${tempB.path}/local_media',
        );
        // (a) production wiring half #1: configureMediaServer.
        serverB.configureMediaServer(mediaServerB);

        try {
          await serverA.start();
          final portB = await serverB.start();

          final bytes = List<int>.generate(8192, (i) => (i * 7) % 256);
          final file = File('${tempA.path}/photo.jpg');
          await file.writeAsBytes(bytes);
          final expectedHash = sha256.convert(bytes).toString();

          // (b) production wiring half #2: consume mediaReadyStream and run the
          // exact persist step lib/main.dart's incomingLocalMediaStream does.
          final persistedPaths = <String>[];
          final sub = serverB.mediaReadyStream!.listen((media) async {
            final persisted = await mediaServerB.persistMedia(
              media.id,
              media.from,
            );
            if (persisted != null) persistedPaths.add(persisted);
          });

          final sent = await serverA.sendMedia(
            host: 'localhost',
            port: portB,
            toPeerId: peerB,
            filePath: file.path,
            mediaId: 'i1-media-001',
            mime: 'image/jpeg',
            fromPeerId: peerA,
          );
          expect(sent, isTrue, reason: 'upload + receiver SHA-256 must verify');

          // Allow the async stream consumer + persistMedia rename to complete.
          await Future.delayed(const Duration(milliseconds: 300));

          expect(
            persistedPaths,
            hasLength(1),
            reason: 'consumer must persist exactly once',
          );
          final persistedPath = persistedPaths.first;

          // Proves the file moved OUT of temp into the persistent media dir
          // (keyed by sender peerId) — the half that protects it from the
          // 5-min pendingTtl GC. Asserting the persisted path, not the temp.
          expect(
            persistedPath.startsWith('${tempB.path}/local_media/$peerA'),
            isTrue,
            reason: 'persisted under mediaDir/<fromPeerId>, got $persistedPath',
          );

          final persistedFile = File(persistedPath);
          expect(await persistedFile.exists(), isTrue);
          final persistedHash =
              sha256.convert(await persistedFile.readAsBytes()).toString();
          expect(
            persistedHash,
            expectedHash,
            reason: 'persisted bytes must match the sender SHA-256',
          );

          // Temp copy must be gone after the rename.
          final tempCopy = File('${tempB.path}/local_media_tmp/i1-media-001.jpg');
          expect(await tempCopy.exists(), isFalse);

          await sub.cancel();
        } finally {
          serverA.dispose();
          serverB.dispose();
          await tempA.delete(recursive: true);
          await tempB.delete(recursive: true);
        }
      },
    );
  });

  // ==========================================================================
  // I2 — unhappy / degraded path
  // ==========================================================================

  group('I2 unhappy: silent server + stale host:port', () {
    test(
      'silent server never acks -> sendMessage false within bounded budget',
      () async {
        final serverA = LocalWsServer();
        // Stand up a raw WS endpoint that accepts but never replies.
        final silent = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        silent.listen((request) {
          WebSocketTransformer.upgrade(request).then(
            (ws) => ws.listen((_) {}),
            onError: (_) {},
          );
        });

        try {
          await serverA.start();

          // Bound the ack wait with an explicit interactive budget so the host
          // test stays fast; matches how the send race caps the local leg.
          final sw = Stopwatch()..start();
          final sent = await serverA.sendMessage(
            'localhost',
            silent.port,
            'never acked',
            peerA,
            peerB,
            timeoutMs: 400,
          );
          sw.stop();

          expect(sent, isFalse, reason: 'no ack -> send must fail');
          expect(
            sw.elapsedMilliseconds,
            greaterThanOrEqualTo(350),
            reason: 'should wait roughly the ack budget',
          );
          expect(
            sw.elapsedMilliseconds,
            lessThan(1500),
            reason: 'must not exceed the interactive local budget',
          );
        } finally {
          await silent.close(force: true);
          serverA.dispose();
        }
      },
    );

    test(
      'stale host:port -> connect fails fast within _connectTimeout (800ms), '
      'not the full local budget',
      () async {
        final serverA = LocalWsServer();
        try {
          await serverA.start();

          // Use a reserved-documentation host (TEST-NET-1) so the TCP connect
          // hangs/refuses rather than resolving — exercises the connect cap.
          // Caller budget is generous (1500ms) so the _connectTimeout cap, not
          // the budget, is what bounds the failure.
          final sw = Stopwatch()..start();
          final sent = await serverA.sendMessage(
            '192.0.2.1',
            54321,
            'to a stale peer',
            peerA,
            peerB,
            timeoutMs: 1500,
          );
          sw.stop();

          expect(sent, isFalse, reason: 'stale host:port must fail');
          // _connectTimeout is 800ms; allow scheduler slack but assert it is
          // bounded well under the 1500ms caller budget — proving the fast cap.
          expect(
            sw.elapsedMilliseconds,
            lessThan(1400),
            reason:
                'connect must abort near _connectTimeout (800ms), not burn the '
                'full 1500ms budget; took ${sw.elapsedMilliseconds}ms',
          );
        } finally {
          serverA.dispose();
        }
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );

    test(
      'stale pooled entry: connect to nothing-listening fails, '
      'next send to a live server on a new port succeeds (F9-style recovery)',
      () async {
        final serverA = LocalWsServer();
        final serverB = LocalWsServer();
        try {
          await serverA.start();

          // First send to a dead port — should fail and evict any pool entry.
          final deadSend = await serverA.sendMessage(
            'localhost',
            19998,
            'to nobody',
            peerA,
            peerB,
            timeoutMs: 1500,
          );
          expect(deadSend, isFalse);

          // Bring up a real receiver and send again to the same peerId.
          final portB = await serverB.start();
          final received = <LocalChatMessage>[];
          final sub = serverB.messageStream.listen(received.add);

          final liveSend = await serverA.sendMessage(
            'localhost',
            portB,
            'after recovery',
            peerA,
            peerB,
          );
          expect(liveSend, isTrue, reason: 'stale entry must not block reuse');

          await Future.delayed(const Duration(milliseconds: 300));
          expect(received, hasLength(1));
          expect(received.first.content, 'after recovery');

          await sub.cancel();
        } finally {
          serverA.dispose();
          serverB.dispose();
        }
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );
  });
}
