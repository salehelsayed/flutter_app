import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/local_discovery/local_discovery_service.dart';
import 'package:flutter_app/core/local_discovery/local_media_server.dart';
import 'package:flutter_app/core/local_discovery/local_p2p_service.dart';
import 'package:flutter_app/core/local_discovery/local_ws_server.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';

import '../../shared/fakes/in_memory_inbox_staging_repository.dart';
import '../local_discovery/fake_local_discovery_service.dart';

/// P3 production-wiring tests.
///
/// These tests exercise the now-wired receive half of the same-WiFi media
/// path END TO END through the production types:
///
///   `PUT /media/<id>`  →  LocalWsServer (configureMediaServer wired)
///                    →  LocalMediaServer.handleUpload  (token-auth +
///                       declared-size + streaming SHA-256)
///                    →  LocalMediaServer.mediaReadyStream
///                    →  LocalP2PService.mediaReadyStream
///                    →  P2PServiceImpl constructor's mediaReadyStream consumer
///                    →  P2PServiceImpl.incomingLocalMediaStream
///
/// The ported [local_media_server_test.dart] tests drive the media server in
/// isolation with their own throwaway HTTP server; here we drive the REAL
/// production wiring (the WS server's own bound port + the P2PServiceImpl
/// consumer) so a regression that drops `configureMediaServer` OR the
/// `mediaReadyStream` consumer is caught.
///
/// U-N2 (negative control) reproduces today's P3 bug: with NO mediaReadyStream
/// consumer reachable (media server not configured), inbound media does NOT
/// surface on `incomingLocalMediaStream`.

class _FakeBridge extends Bridge {
  @override
  bool get isInitialized => true;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> checkHealth() async => true;

  @override
  Future<void> reinitialize() async {}

  @override
  void dispose() {}

  @override
  Future<String> send(String message) async {
    final request = jsonDecode(message) as Map<String, dynamic>;
    final cmd = request['cmd'] as String;
    if (cmd == 'node:start') {
      return jsonEncode({
        'ok': true,
        'peerId': 'self-peer',
        'isStarted': true,
        'listenAddresses': [],
        'circuitAddresses': [],
        'connections': [],
      });
    }
    return jsonEncode({'ok': false, 'errorCode': 'UNHANDLED'});
  }
}

void main() {
  // The HTTP/WebSocket plumbing uses real sockets; keep the binary harness
  // shape identical to the ported local_media_server_test.dart.
  group('P2PServiceImpl local media production wiring', () {
    late Directory tempRoot;
    late Directory mediaDir;
    late LocalMediaServer mediaServer;
    late LocalWsServer wsServer;
    late FakeLocalDiscoveryService discovery;
    late LocalP2PService localP2P;
    late P2PServiceImpl service;
    late int wsPort;

    /// Mirrors main.dart's production wiring: build the media server, hand it
    /// to LocalWsServer.configureMediaServer, compose LocalP2PService, and wrap
    /// it in a real P2PServiceImpl (which subscribes to mediaReadyStream in its
    /// constructor).
    Future<void> wireProduction({required bool configureMedia}) async {
      mediaServer = LocalMediaServer(
        tempDir: '${tempRoot.path}/local_media_tmp',
        mediaDir: mediaDir.path,
      );
      wsServer = LocalWsServer(idleTimeout: const Duration(seconds: 2));
      if (configureMedia) {
        wsServer.configureMediaServer(mediaServer);
      }
      discovery = FakeLocalDiscoveryService();
      localP2P = LocalP2PService(discovery: discovery, wsServer: wsServer);
      service = P2PServiceImpl(
        bridge: _FakeBridge(),
        localP2PService: localP2P,
        inboxStagingRepository: InMemoryInboxStagingRepository(),
      );

      // Start the WS server (binds the random port the receiver advertises).
      await localP2P.start('self-peer');
      wsPort = wsServer.port!;
    }

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp('p2p_media_wiring_');
      mediaDir = await Directory(
        '${tempRoot.path}/media',
      ).create(recursive: true);
    });

    tearDown(() async {
      service.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      try {
        await tempRoot.delete(recursive: true);
      } catch (_) {}
    });

    (List<int>, String) makeBytes(int size) {
      final random = Random(7);
      final bytes = List<int>.generate(size, (_) => random.nextInt(256));
      final hash = sha256.convert(bytes).toString();
      return (bytes, hash);
    }

    /// Open a WS connection to the receiver's server and send a media_offer,
    /// returning the receiver's reply frame (decoded JSON).
    Future<Map<String, dynamic>> sendOffer(MediaOffer offer) async {
      final ws = await WebSocket.connect('ws://localhost:$wsPort');
      final reply = Completer<Map<String, dynamic>>();
      ws.listen((data) {
        if (data is String && !reply.isCompleted) {
          reply.complete(jsonDecode(data) as Map<String, dynamic>);
        }
      });
      ws.add(jsonEncode(offer.toJson()));
      final result = await reply.future.timeout(const Duration(seconds: 5));
      await ws.close();
      return result;
    }

    Future<HttpClientResponse> putMedia(
      String mediaId,
      List<int> body, {
      String? authToken,
      String contentType = 'image/jpeg',
      int? contentLengthOverride,
    }) async {
      final client = HttpClient();
      try {
        final req = await client.openUrl(
          'PUT',
          Uri.parse('http://localhost:$wsPort/media/$mediaId'),
        );
        if (authToken != null) {
          req.headers.set('Authorization', 'Bearer $authToken');
        }
        req.headers.contentType = ContentType.parse(contentType);
        req.headers.set(
          'Content-Length',
          '${contentLengthOverride ?? body.length}',
        );
        req.add(body);
        return await req.close();
      } finally {
        client.close();
      }
    }

    MediaOffer offerFor({
      required String id,
      required int size,
      required String sha256hex,
      String mime = 'image/jpeg',
      String token = 'tok-123',
      String nonce = 'nonce-1',
    }) {
      return MediaOffer(
        id: id,
        from: 'senderPeer',
        to: 'self-peer',
        mime: mime,
        size: size,
        sha256: sha256hex,
        token: token,
        nonce: nonce,
      );
    }

    test(
      'U4 happy: inbound PUT surfaces on incomingLocalMediaStream via the '
      'wired consumer (offer accepted, SHA-256 verified, file on disk)',
      () async {
        await wireProduction(configureMedia: true);

        const size = 2048;
        final (bytes, hash) = makeBytes(size);

        // Capture what the production consumer surfaces.
        final received = <LocalMediaReady>[];
        final sub = service.incomingLocalMediaStream.listen(received.add);
        addTearDown(sub.cancel);

        // 1) Offer over WS — server must accept and echo the token back.
        final offerReply = await sendOffer(
          offerFor(id: 'media-happy', size: size, sha256hex: hash),
        );
        expect(offerReply['type'], 'media_offer_accepted');
        expect(offerReply['id'], 'media-happy');
        expect(offerReply['token'], 'tok-123');

        // 2) PUT the bytes with the granted token.
        final response = await putMedia(
          'media-happy',
          bytes,
          authToken: 'tok-123',
        );
        expect(response.statusCode, HttpStatus.ok);
        await response.drain<void>();

        // 3) The media must reach the production incoming pipeline.
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(
          received,
          hasLength(1),
          reason: 'media must surface on P2PServiceImpl.incomingLocalMediaStream',
        );
        final media = received.single;
        expect(media.id, 'media-happy');
        expect(media.from, 'senderPeer');
        expect(media.to, 'self-peer');
        expect(media.size, size);
        expect(media.sha256, hash);
        expect(media.mime, 'image/jpeg');

        // 4) The streamed file must exist on disk at the reported path.
        final saved = File(media.localPath);
        expect(await saved.exists(), isTrue);
        expect(await saved.length(), size);
      },
    );

    test(
      'enforces token-auth on the production-wired route: missing token → 401, '
      'wrong token → 403, and neither surfaces media',
      () async {
        await wireProduction(configureMedia: true);

        const size = 64;
        final (bytes, hash) = makeBytes(size);

        final received = <LocalMediaReady>[];
        final sub = service.incomingLocalMediaStream.listen(received.add);
        addTearDown(sub.cancel);

        final reply = await sendOffer(
          offerFor(id: 'media-auth', size: size, sha256hex: hash),
        );
        expect(reply['type'], 'media_offer_accepted');

        // Missing Authorization → 401.
        final noAuth = await putMedia('media-auth', bytes);
        expect(noAuth.statusCode, HttpStatus.unauthorized);
        await noAuth.drain<void>();

        // Wrong token → 403 (offer still pending after a rejected auth).
        final wrong = await putMedia(
          'media-auth',
          bytes,
          authToken: 'wrong-token',
        );
        expect(wrong.statusCode, HttpStatus.forbidden);
        await wrong.drain<void>();

        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(received, isEmpty);
      },
    );

    test(
      'enforces declared-size on the production-wired route: more bytes than '
      'declared → 413 and nothing surfaces',
      () async {
        await wireProduction(configureMedia: true);

        // Declare 10 bytes but the offer must still be valid; PUT 100 bytes.
        final reply = await sendOffer(
          offerFor(id: 'media-oversize', size: 10, sha256hex: 'irrelevant'),
        );
        expect(reply['type'], 'media_offer_accepted');

        final received = <LocalMediaReady>[];
        final sub = service.incomingLocalMediaStream.listen(received.add);
        addTearDown(sub.cancel);

        final response = await putMedia(
          'media-oversize',
          List<int>.filled(100, 42),
          authToken: 'tok-123',
        );
        expect(response.statusCode, HttpStatus.requestEntityTooLarge);
        await response.drain<void>();

        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(received, isEmpty);
      },
    );

    test(
      'enforces streaming SHA-256 on the production-wired route: hash mismatch '
      '→ 400, temp file deleted, nothing surfaces',
      () async {
        await wireProduction(configureMedia: true);

        const size = 256;
        final (bytes, _) = makeBytes(size);

        final received = <LocalMediaReady>[];
        final sub = service.incomingLocalMediaStream.listen(received.add);
        addTearDown(sub.cancel);

        final reply = await sendOffer(
          offerFor(
            id: 'media-badhash',
            size: size,
            sha256hex: 'deadbeef-not-the-real-hash',
          ),
        );
        expect(reply['type'], 'media_offer_accepted');

        final response = await putMedia(
          'media-badhash',
          bytes,
          authToken: 'tok-123',
        );
        expect(response.statusCode, HttpStatus.badRequest);
        await response.drain<void>();

        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(received, isEmpty);

        // Temp file must have been deleted on hash mismatch.
        final tempFile = File(
          '${tempRoot.path}/local_media_tmp/media-badhash.jpg',
        );
        expect(await tempFile.exists(), isFalse);
      },
    );

    test(
      'unknown media ID (no prior offer) → 404 on the production-wired route',
      () async {
        await wireProduction(configureMedia: true);

        final received = <LocalMediaReady>[];
        final sub = service.incomingLocalMediaStream.listen(received.add);
        addTearDown(sub.cancel);

        final response = await putMedia(
          'never-offered',
          [1, 2, 3],
          authToken: 'tok-123',
        );
        expect(response.statusCode, HttpStatus.notFound);
        await response.drain<void>();

        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(received, isEmpty);
      },
    );

    // ---------------------------------------------------------------------
    // NEGATIVE CONTROL U-N2
    // ---------------------------------------------------------------------
    // Reproduces today's P3 bug: with NO mediaReadyStream consumer reachable
    // (media server NOT configured on the WS server), inbound media does NOT
    // surface. This is what proves the happy-path test isn't passing by
    // accident — a future regression that drops configureMediaServer (or the
    // P2PServiceImpl consumer that subscribes to mediaReadyStream) is caught.
    test(
      'U-N2: with NO media server configured, the WS server has no '
      'mediaReadyStream so P2PServiceImpl never subscribes; inbound PUT → 404 '
      'and nothing surfaces on incomingLocalMediaStream',
      () async {
        await wireProduction(configureMedia: false);

        // The whole point: the consumer the P2PServiceImpl constructor would
        // attach is null, because LocalWsServer.mediaReadyStream is null when
        // the media server was never configured.
        expect(
          localP2P.mediaReadyStream,
          isNull,
          reason:
              'precondition for U-N2: dropping configureMediaServer leaves no '
              'mediaReadyStream for P2PServiceImpl to consume',
        );

        final received = <LocalMediaReady>[];
        final sub = service.incomingLocalMediaStream.listen(received.add);
        addTearDown(sub.cancel);

        // A media_offer is rejected because the media server is absent.
        final reply = await sendOffer(
          offerFor(id: 'media-none', size: 16, sha256hex: 'abc'),
        );
        expect(reply['type'], 'media_offer_rejected');
        expect(reply['reason'], 'media_not_supported');

        // And a raw PUT (even with a token) gets 404 — no upload path exists.
        final response = await putMedia(
          'media-none',
          List<int>.filled(16, 1),
          authToken: 'tok-123',
        );
        expect(response.statusCode, HttpStatus.notFound);
        await response.drain<void>();

        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(
          received,
          isEmpty,
          reason:
              'today\'s P3 bug: without the media server + consumer, local '
              'media never reaches the incoming pipeline',
        );
      },
    );
  });
}
