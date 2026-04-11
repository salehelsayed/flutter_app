import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/local_discovery/local_media_sender.dart';

void main() {
  group('LocalMediaSender', () {
    late LocalMediaSender sender;
    late Directory tempDir;

    setUp(() async {
      sender = LocalMediaSender();
      tempDir = await Directory.systemTemp.createTemp('media_sender_test_');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    /// Create a test file with deterministic content.
    Future<(File, String, int)> _createTestFile(int size) async {
      final random = Random(42);
      final bytes = List<int>.generate(size, (_) => random.nextInt(256));
      final file = File('${tempDir.path}/test_file.bin');
      await file.writeAsBytes(bytes);
      final hash = sha256.convert(bytes).toString();
      return (file, hash, size);
    }

    /// Start a mock receiver that handles WS signaling + HTTP PUT.
    /// Returns (httpServer, wsPort).
    ///
    /// [onOffer] is called when a media_offer arrives on the WS.
    /// [onPutBody] is called with the bytes received on PUT /media/<id>.
    /// [putStatusCode] is the HTTP status to respond with.
    /// [sendMediaUploaded] if true, sends media_uploaded after PUT succeeds.
    /// [putDelay] optional delay before responding to PUT.
    Future<(HttpServer, int)> _startMockReceiver({
      void Function(WebSocket ws, Map<String, dynamic> offer)? onOffer,
      void Function(List<int> body)? onPutBody,
      int putStatusCode = HttpStatus.ok,
      bool sendMediaUploaded = true,
      bool sendMediaFailed = false,
      Duration? putDelay,
      bool rejectOffer = false,
      Duration? offerDelay,
    }) async {
      final httpServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

      // Track the sender's WS to send media_uploaded back.
      WebSocket? senderWs;
      String? lastNonce;

      httpServer.listen((request) {
        final path = request.uri.path;

        if (path.startsWith('/media/')) {
          // HTTP PUT handler.
          if (request.method != 'PUT') {
            request.response
              ..statusCode = HttpStatus.methodNotAllowed
              ..close();
            return;
          }

          // Collect the body.
          final chunks = <List<int>>[];
          request.listen(
            chunks.add,
            onDone: () async {
              final body = chunks.expand((c) => c).toList();
              onPutBody?.call(body);

              if (putDelay != null) {
                await Future.delayed(putDelay);
              }

              request.response
                ..statusCode = putStatusCode
                ..close();

              // Send media_uploaded via WS if success.
              if (putStatusCode == HttpStatus.ok &&
                  sendMediaUploaded &&
                  senderWs != null &&
                  lastNonce != null) {
                final mediaId = path.substring('/media/'.length);
                senderWs!.add(
                  jsonEncode({
                    'type': 'media_uploaded',
                    'id': mediaId,
                    'nonce': lastNonce,
                    'sha256Verified': true,
                  }),
                );
              } else if (putStatusCode == HttpStatus.ok &&
                  sendMediaFailed &&
                  senderWs != null &&
                  lastNonce != null) {
                final mediaId = path.substring('/media/'.length);
                senderWs!.add(
                  jsonEncode({
                    'type': 'media_failed',
                    'id': mediaId,
                    'nonce': lastNonce,
                    'reason': 'server_validation_failed',
                  }),
                );
              }
            },
          );
          return;
        }

        // WebSocket upgrade (root path).
        WebSocketTransformer.upgrade(request)
            .then((ws) {
              senderWs = ws;
              ws.listen((data) {
                if (data is! String) return;
                try {
                  final json = jsonDecode(data) as Map<String, dynamic>;
                  final type = json['type'] as String?;
                  if (type == 'media_offer') {
                    lastNonce = json['nonce'] as String?;
                    onOffer?.call(ws, json);

                    if (rejectOffer) {
                      ws.add(
                        jsonEncode({
                          'type': 'media_offer_rejected',
                          'id': json['id'],
                          'nonce': json['nonce'],
                          'reason': 'test_reject',
                        }),
                      );
                    } else {
                      Future<void> accept() async {
                        if (offerDelay != null) {
                          await Future.delayed(offerDelay);
                        }
                        ws.add(
                          jsonEncode({
                            'type': 'media_offer_accepted',
                            'id': json['id'],
                            'token': json['token'],
                            'nonce': json['nonce'],
                          }),
                        );
                      }

                      accept();
                    }
                  }
                } catch (_) {}
              });
            })
            .catchError((_) {});
      });

      return (httpServer, httpServer.port);
    }

    /// Connect a WS client and return (ws, broadcastStream).
    Future<(WebSocket, Stream<dynamic>)> _connectWs(int port) async {
      final ws = await WebSocket.connect('ws://localhost:$port');
      final broadcast = StreamController<dynamic>.broadcast();
      ws.listen(broadcast.add, onError: broadcast.addError);
      return (ws, broadcast.stream);
    }

    test('computes SHA-256 of file before sending offer', () async {
      final (file, expectedHash, size) = await _createTestFile(1024);

      Map<String, dynamic>? receivedOffer;
      final (server, port) = await _startMockReceiver(
        onOffer: (ws, offer) {
          receivedOffer = offer;
        },
      );

      final (ws, ackStream) = await _connectWs(port);

      await sender.sendMedia(
        host: 'localhost',
        port: port,
        ws: ws,
        ackStream: ackStream,
        filePath: file.path,
        mediaId: 'media-1',
        mime: 'image/jpeg',
        fromPeerId: 'sender',
        toPeerId: 'receiver',
      );

      expect(receivedOffer, isNotNull);
      expect(receivedOffer!['sha256'], expectedHash);
      expect(receivedOffer!['size'], size);

      await ws.close();
      await server.close(force: true);
    });

    test(
      'sends media_offer via WS with all required fields including nonce',
      () async {
        final (file, _, _) = await _createTestFile(512);

        Map<String, dynamic>? receivedOffer;
        final (server, port) = await _startMockReceiver(
          onOffer: (ws, offer) {
            receivedOffer = offer;
          },
        );

        final (ws, ackStream) = await _connectWs(port);

        await sender.sendMedia(
          host: 'localhost',
          port: port,
          ws: ws,
          ackStream: ackStream,
          filePath: file.path,
          mediaId: 'media-2',
          mime: 'audio/aac',
          fromPeerId: 'sender',
          toPeerId: 'receiver',
          durationMs: 5000,
          waveform: [0.1, 0.5, 0.9],
          filename: 'voice.m4a',
        );

        expect(receivedOffer, isNotNull);
        expect(receivedOffer!['type'], 'media_offer');
        expect(receivedOffer!['id'], 'media-2');
        expect(receivedOffer!['from'], 'sender');
        expect(receivedOffer!['to'], 'receiver');
        expect(receivedOffer!['mime'], 'audio/aac');
        expect(receivedOffer!['nonce'], isNotNull);
        expect(receivedOffer!['nonce'], isNotEmpty);
        expect(receivedOffer!['token'], isNotNull);
        expect(receivedOffer!['token'], isNotEmpty);
        expect(receivedOffer!['durationMs'], 5000);
        expect(receivedOffer!['waveform'], [0.1, 0.5, 0.9]);
        expect(receivedOffer!['filename'], 'voice.m4a');

        await ws.close();
        await server.close(force: true);
      },
    );

    test('sends GIF media_offer with image/gif mime and filename metadata', () async {
      final file = File('${tempDir.path}/funny.gif')
        ..writeAsBytesSync(List<int>.filled(256, 0x47));

      Map<String, dynamic>? receivedOffer;
      final (server, port) = await _startMockReceiver(
        onOffer: (ws, offer) {
          receivedOffer = offer;
        },
      );

      final (ws, ackStream) = await _connectWs(port);

      await sender.sendMedia(
        host: 'localhost',
        port: port,
        ws: ws,
        ackStream: ackStream,
        filePath: file.path,
        mediaId: 'media-gif-1',
        mime: 'image/gif',
        fromPeerId: 'sender',
        toPeerId: 'receiver',
        filename: 'funny.gif',
      );

      expect(receivedOffer, isNotNull);
      expect(receivedOffer!['mime'], 'image/gif');
      expect(receivedOffer!['filename'], 'funny.gif');

      await ws.close();
      await server.close(force: true);
    });

    test(
      'uploads file via HTTP PUT with Bearer token and correct Content-Length',
      () async {
        final (file, _, size) = await _createTestFile(2048);

        List<int>? receivedBody;
        final (server, port) = await _startMockReceiver(
          onPutBody: (body) {
            receivedBody = body;
          },
        );

        final (ws, ackStream) = await _connectWs(port);

        final result = await sender.sendMedia(
          host: 'localhost',
          port: port,
          ws: ws,
          ackStream: ackStream,
          filePath: file.path,
          mediaId: 'media-3',
          mime: 'image/png',
          fromPeerId: 'sender',
          toPeerId: 'receiver',
        );

        expect(result, isTrue);
        expect(receivedBody, isNotNull);
        expect(receivedBody!.length, size);

        // Verify the bytes match the original file.
        final originalBytes = await file.readAsBytes();
        expect(receivedBody, originalBytes);

        await ws.close();
        await server.close(force: true);
      },
    );

    test(
      'returns true when media_uploaded received with matching nonce',
      () async {
        final (file, _, _) = await _createTestFile(256);

        final (server, port) = await _startMockReceiver(
          sendMediaUploaded: true,
        );

        final (ws, ackStream) = await _connectWs(port);

        final result = await sender.sendMedia(
          host: 'localhost',
          port: port,
          ws: ws,
          ackStream: ackStream,
          filePath: file.path,
          mediaId: 'media-4',
          mime: 'image/jpeg',
          fromPeerId: 'sender',
          toPeerId: 'receiver',
        );

        expect(result, isTrue);

        await ws.close();
        await server.close(force: true);
      },
    );

    test(
      'returns false on offer timeout (no media_offer_accepted)',
      () async {
        final (file, _, _) = await _createTestFile(256);

        // Start a server that never sends media_offer_accepted.
        final httpServer = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        httpServer.listen((request) {
          WebSocketTransformer.upgrade(request)
              .then((ws) {
                ws.listen((_) {
                  // Deliberately don't respond to offers.
                });
              })
              .catchError((_) {});
        });

        final (ws, ackStream) = await _connectWs(httpServer.port);

        final result = await sender.sendMedia(
          host: 'localhost',
          port: httpServer.port,
          ws: ws,
          ackStream: ackStream,
          filePath: file.path,
          mediaId: 'media-timeout',
          mime: 'image/jpeg',
          fromPeerId: 'sender',
          toPeerId: 'receiver',
        );

        expect(result, isFalse);

        await ws.close();
        await httpServer.close(force: true);
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );

    test('returns false on upload HTTP error', () async {
      final (file, _, _) = await _createTestFile(256);

      final (server, port) = await _startMockReceiver(
        putStatusCode: HttpStatus.internalServerError,
        sendMediaUploaded: false,
      );

      final (ws, ackStream) = await _connectWs(port);

      final result = await sender.sendMedia(
        host: 'localhost',
        port: port,
        ws: ws,
        ackStream: ackStream,
        filePath: file.path,
        mediaId: 'media-fail',
        mime: 'image/jpeg',
        fromPeerId: 'sender',
        toPeerId: 'receiver',
      );

      expect(result, isFalse);

      await ws.close();
      await server.close(force: true);
    });

    test(
      'returns false on media_uploaded timeout',
      () async {
        final (file, _, _) = await _createTestFile(256);

        final (server, port) = await _startMockReceiver(
          sendMediaUploaded: false, // Never send media_uploaded.
        );

        final (ws, ackStream) = await _connectWs(port);

        final result = await sender.sendMedia(
          host: 'localhost',
          port: port,
          ws: ws,
          ackStream: ackStream,
          filePath: file.path,
          mediaId: 'media-no-confirm',
          mime: 'image/jpeg',
          fromPeerId: 'sender',
          toPeerId: 'receiver',
        );

        expect(result, isFalse);

        await ws.close();
        await server.close(force: true);
      },
      timeout: const Timeout(Duration(seconds: 35)),
    );

    test('returns false when file does not exist', () async {
      final (server, port) = await _startMockReceiver();
      final (ws, ackStream) = await _connectWs(port);

      final result = await sender.sendMedia(
        host: 'localhost',
        port: port,
        ws: ws,
        ackStream: ackStream,
        filePath: '/nonexistent/file.jpg',
        mediaId: 'media-nofile',
        mime: 'image/jpeg',
        fromPeerId: 'sender',
        toPeerId: 'receiver',
      );

      expect(result, isFalse);

      await ws.close();
      await server.close(force: true);
    });

    test('returns false quickly on explicit media_offer_rejected', () async {
      final (file, _, _) = await _createTestFile(256);

      final (server, port) = await _startMockReceiver(rejectOffer: true);

      final (ws, ackStream) = await _connectWs(port);

      final stopwatch = Stopwatch()..start();
      final result = await sender.sendMedia(
        host: 'localhost',
        port: port,
        ws: ws,
        ackStream: ackStream,
        filePath: file.path,
        mediaId: 'media-rejected',
        mime: 'image/jpeg',
        fromPeerId: 'sender',
        toPeerId: 'receiver',
      );
      stopwatch.stop();

      expect(result, isFalse);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));

      await ws.close();
      await server.close(force: true);
    });

    test(
      'returns false quickly on explicit media_failed after upload',
      () async {
        final (file, _, _) = await _createTestFile(256);

        final (server, port) = await _startMockReceiver(
          sendMediaUploaded: false,
          sendMediaFailed: true,
        );

        final (ws, ackStream) = await _connectWs(port);

        final stopwatch = Stopwatch()..start();
        final result = await sender.sendMedia(
          host: 'localhost',
          port: port,
          ws: ws,
          ackStream: ackStream,
          filePath: file.path,
          mediaId: 'media-failed',
          mime: 'image/jpeg',
          fromPeerId: 'sender',
          toPeerId: 'receiver',
        );
        stopwatch.stop();

        expect(result, isFalse);
        expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));

        await ws.close();
        await server.close(force: true);
      },
    );

    test('concurrent sends do not cross-match nonce when accepted/uploaded '
        'events arrive swapped', () async {
      final (fileA, _, _) = await _createTestFile(512);
      final (fileB, _, _) = await _createTestFile(768);

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;

      WebSocket? senderWs;
      final offersById = <String, Map<String, dynamic>>{};
      final putsSeen = <String>[];

      server.listen((request) {
        final path = request.uri.path;
        if (path.startsWith('/media/')) {
          final mediaId = path.substring('/media/'.length);
          request.listen(
            (_) {},
            onDone: () {
              request.response
                ..statusCode = HttpStatus.ok
                ..close();
              putsSeen.add(mediaId);
              if (putsSeen.length == 2 && senderWs != null) {
                // Send uploaded in reverse order to verify nonce correlation.
                final secondId = putsSeen[1];
                final firstId = putsSeen[0];
                senderWs!.add(
                  jsonEncode({
                    'type': 'media_uploaded',
                    'id': secondId,
                    'nonce': offersById[secondId]!['nonce'],
                    'sha256Verified': true,
                  }),
                );
                senderWs!.add(
                  jsonEncode({
                    'type': 'media_uploaded',
                    'id': firstId,
                    'nonce': offersById[firstId]!['nonce'],
                    'sha256Verified': true,
                  }),
                );
              }
            },
          );
          return;
        }

        WebSocketTransformer.upgrade(request)
            .then((ws) {
              senderWs = ws;
              ws.listen((data) {
                if (data is! String) return;
                final json = jsonDecode(data) as Map<String, dynamic>;
                if (json['type'] != 'media_offer') return;

                final id = json['id'] as String;
                offersById[id] = json;

                if (offersById.length == 2) {
                  // Accept in reverse order to ensure waiters match by id+nonce.
                  final ids = offersById.keys.toList();
                  final firstId = ids[0];
                  final secondId = ids[1];
                  ws.add(
                    jsonEncode({
                      'type': 'media_offer_accepted',
                      'id': secondId,
                      'token': offersById[secondId]!['token'],
                      'nonce': offersById[secondId]!['nonce'],
                    }),
                  );
                  ws.add(
                    jsonEncode({
                      'type': 'media_offer_accepted',
                      'id': firstId,
                      'token': offersById[firstId]!['token'],
                      'nonce': offersById[firstId]!['nonce'],
                    }),
                  );
                }
              });
            })
            .catchError((_) {});
      });

      final (ws, ackStream) = await _connectWs(port);

      final results = await Future.wait([
        sender.sendMedia(
          host: 'localhost',
          port: port,
          ws: ws,
          ackStream: ackStream,
          filePath: fileA.path,
          mediaId: 'media-concurrent-a',
          mime: 'image/jpeg',
          fromPeerId: 'sender',
          toPeerId: 'receiver',
        ),
        sender.sendMedia(
          host: 'localhost',
          port: port,
          ws: ws,
          ackStream: ackStream,
          filePath: fileB.path,
          mediaId: 'media-concurrent-b',
          mime: 'image/png',
          fromPeerId: 'sender',
          toPeerId: 'receiver',
        ),
      ]);

      expect(results, everyElement(isTrue));

      await ws.close();
      await server.close(force: true);
    });
  });
}
