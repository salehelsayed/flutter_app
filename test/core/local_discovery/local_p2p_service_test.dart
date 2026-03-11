import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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
  });
}

class _RecordingLocalWsServer extends LocalWsServer {
  int? lastTimeoutMs;
  String? lastToPeerId;

  @override
  Future<bool> sendMessage(
    String host,
    int port,
    String content,
    String fromPeerId,
    String toPeerId, {
    int? timeoutMs,
  }) async {
    lastTimeoutMs = timeoutMs;
    lastToPeerId = toPeerId;
    return true;
  }
}
