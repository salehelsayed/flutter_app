import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/local_discovery/lan_ack.dart';
import 'package:flutter_app/core/local_discovery/local_discovery_service.dart';
import 'package:flutter_app/core/local_discovery/local_media_server.dart';
import 'package:flutter_app/core/local_discovery/local_ws_server.dart';
import 'package:flutter_app/core/local_discovery/local_p2p_service.dart';

import 'fake_local_discovery_service.dart';

void main() {
  group('LocalP2PService', () {
    late FakeLocalDiscoveryService fakeDiscovery;
    late LocalWsServer wsServer;
    late LocalP2PService service;

    setUp(() {
      fakeDiscovery = FakeLocalDiscoveryService();
      wsServer = LocalWsServer(idleTimeout: const Duration(seconds: 2));
      service = LocalP2PService(discovery: fakeDiscovery, wsServer: wsServer);
    });

    tearDown(() {
      service.dispose();
    });

    test('start launches WS server and advertises', () async {
      await service.start('myPeerId');

      expect(wsServer.port, isNotNull);
      expect(fakeDiscovery.isAdvertising, isTrue);
      expect(fakeDiscovery.advertisedPeerId, equals('myPeerId'));
      expect(fakeDiscovery.advertisedPort, equals(wsServer.port));
    });

    // FDC-11 (174) TC-02: once the host surfaces its resolved libp2p LAN ports
    // (after the cold-start early seam advertised null), updateLibp2pPorts
    // re-advertises with the fresh ports and updates the cache so a later
    // restartAdvertising re-publishes them.
    test('updateLibp2pPorts re-advertises with fresh libp2p ports', () async {
      await service.start('peer', quicPort: null, tcpPort: null);
      expect(fakeDiscovery.advertisedQuicPort, isNull);
      expect(fakeDiscovery.advertisedTcpPort, isNull);
      expect(fakeDiscovery.startAdvertisingCallCount, 1);

      await service.updateLibp2pPorts(quicPort: 45000, tcpPort: 45001);

      expect(fakeDiscovery.advertisedQuicPort, 45000);
      expect(fakeDiscovery.advertisedTcpPort, 45001);
      expect(
        fakeDiscovery.startAdvertisingCallCount,
        2,
        reason: 're-advertise must re-issue startAdvertising',
      );

      // Cache updated: a later restartAdvertising re-publishes the fresh ports
      // (not the stale cold-start null).
      await service.restartAdvertising();
      expect(fakeDiscovery.advertisedQuicPort, 45000);
      expect(fakeDiscovery.advertisedTcpPort, 45001);
    });

    // FDC-11 (174) TC-02 edge: partial resolution — only the QUIC port is known
    // — still re-advertises (quic non-null, tcp null).
    test('updateLibp2pPorts advertises a quic-only subset', () async {
      await service.start('peer');
      expect(fakeDiscovery.startAdvertisingCallCount, 1);

      await service.updateLibp2pPorts(quicPort: 45000, tcpPort: null);

      expect(fakeDiscovery.advertisedQuicPort, 45000);
      expect(fakeDiscovery.advertisedTcpPort, isNull);
      expect(fakeDiscovery.startAdvertisingCallCount, 2);
    });

    // FDC-11 (174) TC-03: unchanged ports must NOT churn the advert. The
    // addresses:updated push can fire many times with the same resolved ports.
    test('updateLibp2pPorts is a no-op when ports unchanged', () async {
      await service.start('peer', quicPort: 45000, tcpPort: 45001);
      expect(fakeDiscovery.startAdvertisingCallCount, 1);

      await service.updateLibp2pPorts(quicPort: 45000, tcpPort: 45001);

      expect(
        fakeDiscovery.startAdvertisingCallCount,
        1,
        reason: 'unchanged ports must not re-advertise',
      );
    });

    // 179 (TC-179-04 / INV-5): when the iOS suspected-denied gate is latched the
    // broadcast (re)start is skipped — so a port self-heal must NOT tear down the
    // prior ported advert (the re-register would never happen, leaving the device
    // advertising nothing). It defers, keeps the working advert, and retries once
    // the gate clears (a resolved peer un-latches it). Reproduces the CV-34
    // sub-cause B that strands the iPhone with a portless/torn-down advert.
    test(
      'TC-179-04: a gated re-advert retains the prior ported advert and retries '
      'after the gate clears',
      () async {
        await service.start('peer', quicPort: 4001, tcpPort: 4002);
        expect(fakeDiscovery.startAdvertisingCallCount, 1);
        expect(fakeDiscovery.stopAdvertisingCallCount, 0);
        expect(fakeDiscovery.advertisedTcpPort, 4002);

        // Gate latched: the broadcast (re)start would be skipped.
        fakeDiscovery.isAdvertiseBroadcastGated = true;
        await service.updateLibp2pPorts(quicPort: 4001, tcpPort: 4003);

        expect(
          fakeDiscovery.stopAdvertisingCallCount,
          0,
          reason: 'a gated re-advert must NOT tear down the prior ported advert',
        );
        expect(
          fakeDiscovery.startAdvertisingCallCount,
          1,
          reason: 'no re-register while the broadcast is gated',
        );
        expect(
          fakeDiscovery.advertisedTcpPort,
          4002,
          reason: 'the prior advert (tcp 4002) is retained, not replaced',
        );

        // Gate clears (a peer resolved → Local Network proven) → retry publishes
        // the fresh ports (the cache was NOT poisoned by the deferred attempt).
        fakeDiscovery.isAdvertiseBroadcastGated = false;
        await service.updateLibp2pPorts(quicPort: 4001, tcpPort: 4003);

        expect(fakeDiscovery.startAdvertisingCallCount, 2);
        expect(fakeDiscovery.advertisedTcpPort, 4003);
      },
    );

    test('stop stops advertising and WS server', () async {
      await service.start('myPeerId');
      await service.stop();

      expect(fakeDiscovery.isAdvertising, isFalse);
      expect(wsServer.port, isNull);
    });

    test('isLocalPeer delegates to discovery', () async {
      await service.start('myPeerId');

      expect(service.isLocalPeer('otherPeer'), isFalse);

      fakeDiscovery.addPeer(
        LocalPeer(
          peerId: 'otherPeer',
          host: '192.168.1.50',
          port: 8888,
          discoveredAt: DateTime.now().toUtc(),
        ),
      );

      expect(service.isLocalPeer('otherPeer'), isTrue);
    });

    test('sendMessage returns false when peer not discovered', () async {
      await service.start('myPeerId');

      final sent = await service.sendMessage(
        'unknownPeer',
        'content',
        'myPeerId',
      );
      expect(sent, isFalse);
    });

    test('sendMessage sends to discovered peer via WS', () async {
      await service.start('myPeerId');

      // Start a second WS server to act as the remote peer.
      final remoteServer = LocalWsServer();
      remoteServer.configureInboundChatCommitHandler(
        (message, {required nonce}) => const LanInboundDecision.committed(),
      );
      final remotePort = await remoteServer.start();

      fakeDiscovery.addPeer(
        LocalPeer(
          peerId: 'remotePeer',
          host: 'localhost',
          port: remotePort,
          discoveredAt: DateTime.now().toUtc(),
        ),
      );

      final sent = await service.sendMessage(
        'remotePeer',
        '{"text":"hi"}',
        'myPeerId',
      );
      expect(sent, isTrue);

      remoteServer.dispose();
    });

    test('sendMessage forwards timeoutMs to the WS transport', () async {
      final recordingWsServer = _RecordingLocalWsServer();
      service = LocalP2PService(
        discovery: fakeDiscovery,
        wsServer: recordingWsServer,
      );

      fakeDiscovery.addPeer(
        LocalPeer(
          peerId: 'remotePeer',
          host: 'localhost',
          port: 4040,
          discoveredAt: DateTime.now().toUtc(),
        ),
      );

      final sent = await service.sendMessage(
        'remotePeer',
        '{"text":"hi"}',
        'myPeerId',
        timeoutMs: 321,
      );

      expect(sent, isTrue);
      expect(recordingWsServer.lastTimeoutMs, 321);
      expect(recordingWsServer.lastToPeerId, 'remotePeer');
    });

    test('sendMessageDetailed returns the WS ack classification', () async {
      final recordingWsServer = _RecordingLocalWsServer()
        ..ack = LanSendAck.legacyAck;
      service = LocalP2PService(
        discovery: fakeDiscovery,
        wsServer: recordingWsServer,
      );

      fakeDiscovery.addPeer(
        LocalPeer(
          peerId: 'remotePeer',
          host: 'localhost',
          port: 4040,
          discoveredAt: DateTime.now().toUtc(),
        ),
      );

      final ack = await service.sendMessageDetailed(
        'remotePeer',
        '{"text":"hi"}',
        'myPeerId',
        timeoutMs: 456,
      );

      expect(ack, LanSendAck.legacyAck);
      expect(recordingWsServer.lastTimeoutMs, 456);
      expect(recordingWsServer.lastToPeerId, 'remotePeer');
      expect(
        await service.sendMessage('remotePeer', '{"text":"hi"}', 'myPeerId'),
        isFalse,
      );
    });

    test('sendMedia returns false when peer not discovered', () async {
      await service.start('myPeerId');

      final tempDir = await Directory.systemTemp.createTemp(
        'local_p2p_send_media_',
      );
      final file = File('${tempDir.path}/image.jpg');
      await file.writeAsBytes([1, 2, 3, 4]);

      final sent = await service.sendMedia(
        peerId: 'unknownPeer',
        filePath: file.path,
        mime: 'image/jpeg',
        mediaId: 'media-unknown',
        fromPeerId: 'myPeerId',
      );
      expect(sent, isFalse);

      await tempDir.delete(recursive: true);
    });

    test(
      'sendMedia delegates to WS media transfer for discovered peer',
      () async {
        await service.start('myPeerId');

        final remoteServer = LocalWsServer();
        final remoteTemp = await Directory.systemTemp.createTemp(
          'local_p2p_remote_media_',
        );
        final remoteMediaServer = LocalMediaServer(
          tempDir: '${remoteTemp.path}/temp',
          mediaDir: '${remoteTemp.path}/media',
        );
        remoteServer.configureMediaServer(remoteMediaServer);
        final remotePort = await remoteServer.start();

        fakeDiscovery.addPeer(
          LocalPeer(
            peerId: 'remotePeer',
            host: 'localhost',
            port: remotePort,
            discoveredAt: DateTime.now().toUtc(),
          ),
        );

        final localTemp = await Directory.systemTemp.createTemp(
          'local_p2p_local_media_',
        );
        final file = File('${localTemp.path}/image.jpg');
        await file.writeAsBytes(List<int>.generate(1024, (i) => i % 256));

        final sent = await service.sendMedia(
          peerId: 'remotePeer',
          filePath: file.path,
          mime: 'image/jpeg',
          mediaId: 'media-delegate',
          fromPeerId: 'myPeerId',
        );

        expect(sent, isTrue);

        remoteServer.dispose();
        await localTemp.delete(recursive: true);
        await remoteTemp.delete(recursive: true);
      },
    );

    test('discoveredPeersStream emits on peer change', () async {
      await service.start('myPeerId');

      final snapshots = <Map<String, LocalPeer>>[];
      final sub = service.discoveredPeersStream.listen(snapshots.add);

      fakeDiscovery.addPeer(
        LocalPeer(
          peerId: 'peer1',
          host: '192.168.1.10',
          port: 5000,
          discoveredAt: DateTime.now().toUtc(),
        ),
      );

      await Future.delayed(const Duration(milliseconds: 50));

      expect(snapshots, hasLength(1));
      expect(snapshots.first.containsKey('peer1'), isTrue);

      fakeDiscovery.removePeer('peer1');

      await Future.delayed(const Duration(milliseconds: 50));

      expect(snapshots, hasLength(2));
      expect(snapshots.last.containsKey('peer1'), isFalse);

      await sub.cancel();
    });

    test('I1 production-wiring: inbound media reaches mediaReadyStream and '
        'persists under the local WS server (real stack)', () async {
      // Receiver side: configure a media server on the service's own WS
      // server so PUT /media/<id> is served (production wiring half #1).
      final recvTemp = await Directory.systemTemp.createTemp(
        'local_p2p_recv_media_',
      );
      final recvMediaServer = LocalMediaServer(
        tempDir: '${recvTemp.path}/local_media_tmp',
        mediaDir: '${recvTemp.path}/local_media',
      );
      wsServer.configureMediaServer(recvMediaServer);

      await service.start('myPeerId');

      // Consume the service's mediaReadyStream and persist, exactly as the
      // production incomingLocalMediaStream consumer does (wiring half #2).
      final persistedPaths = <String>[];
      final sub = service.mediaReadyStream?.listen((media) async {
        final persisted = await recvMediaServer.persistMedia(
          media.id,
          media.from,
        );
        if (persisted != null) persistedPaths.add(persisted);
      });
      expect(sub, isNotNull, reason: 'mediaReadyStream must be live');

      // Sender side: a second WS server uploads a file to us.
      final senderServer = LocalWsServer();
      await senderServer.start();
      final senderTemp = await Directory.systemTemp.createTemp(
        'local_p2p_sender_media_',
      );
      final bytes = List<int>.generate(2048, (i) => (i * 3) % 256);
      final file = File('${senderTemp.path}/image.jpg');
      await file.writeAsBytes(bytes);
      final expectedHash = sha256.convert(bytes).toString();

      final sent = await senderServer.sendMedia(
        host: 'localhost',
        port: wsServer.port!,
        toPeerId: 'myPeerId',
        filePath: file.path,
        mediaId: 'i1-stack-media-1',
        mime: 'image/jpeg',
        fromPeerId: 'senderPeer',
      );
      expect(sent, isTrue);

      await Future.delayed(const Duration(milliseconds: 300));

      expect(persistedPaths, hasLength(1));
      final persistedFile = File(persistedPaths.first);
      expect(await persistedFile.exists(), isTrue);
      final persistedHash = sha256
          .convert(await persistedFile.readAsBytes())
          .toString();
      expect(persistedHash, expectedHash);

      await sub?.cancel();
      senderServer.dispose();
      await senderTemp.delete(recursive: true);
      await recvTemp.delete(recursive: true);
    });

    test('localMessageStream emits messages received by WS server', () async {
      await service.start('myPeerId');

      // Set up a future that completes when the first message arrives.
      final firstMessage = service.localMessageStream.first;

      // Connect to the WS server as a remote peer and send a message.
      final port = wsServer.port!;
      final ws = await WebSocket.connect('ws://localhost:$port');
      ws.add(
        '{"from":"remotePeer","to":"myPeerId","content":"{\\"text\\":\\"hello\\"}"}',
      );

      // Wait for the ack to ensure the server processed it.
      await ws.first;

      final msg = await firstMessage.timeout(const Duration(seconds: 2));

      expect(msg.from, equals('remotePeer'));
      expect(msg.content, equals('{"text":"hello"}'));

      await ws.close();
    });

    test(
      'configureInboundChatCommitHandler delegates to LocalWsServer',
      () async {
        await service.start('myPeerId');

        LocalChatMessage? handledMessage;
        String? handledNonce;
        service.configureInboundChatCommitHandler((message, {required nonce}) {
          handledMessage = message;
          handledNonce = nonce;
          return const LanInboundDecision.accepted();
        });

        final port = wsServer.port!;
        final ws = await WebSocket.connect('ws://localhost:$port');
        ws.add(
          '{"from":"remotePeer","to":"myPeerId","content":"{\\"type\\":\\"chat_message\\"}","nonce":"lan-n1"}',
        );

        await ws.first.timeout(const Duration(seconds: 2));

        expect(handledMessage, isNotNull);
        expect(handledMessage!.from, 'remotePeer');
        expect(handledMessage!.to, 'myPeerId');
        expect(handledMessage!.content, '{"type":"chat_message"}');
        expect(handledNonce, 'lan-n1');

        await ws.close();
      },
    );
  });
}

class _RecordingLocalWsServer extends LocalWsServer {
  int? lastTimeoutMs;
  String? lastToPeerId;
  LanSendAck ack = LanSendAck.committed;

  @override
  Future<LanSendAck> sendMessageWithAck(
    String host,
    int port,
    String content,
    String fromPeerId,
    String toPeerId, {
    int? timeoutMs,
  }) async {
    lastTimeoutMs = timeoutMs;
    lastToPeerId = toPeerId;
    return ack;
  }
}
