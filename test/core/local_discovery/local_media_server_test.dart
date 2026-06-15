import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/local_discovery/local_media_server.dart';
import 'package:flutter_app/core/local_discovery/local_discovery_service.dart';

void main() {
  group('LocalMediaServer', () {
    late LocalMediaServer mediaServer;
    late Directory tempDir;
    late Directory mediaDir;
    late HttpServer testHttpServer;
    late int serverPort;

    LocalMediaServer _createMediaServer({int? maxAcceptedFileSizeBytes}) {
      return LocalMediaServer(
        tempDir: '${tempDir.path}/temp',
        mediaDir: mediaDir.path,
        maxAcceptedFileSizeBytes: maxAcceptedFileSizeBytes,
      );
    }

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('media_server_test_');
      mediaDir = await Directory(
        '${tempDir.path}/media',
      ).create(recursive: true);

      mediaServer = _createMediaServer();

      // Start an HTTP server that delegates /media/* to the media server.
      testHttpServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      serverPort = testHttpServer.port;
      testHttpServer.listen((request) {
        final path = request.uri.path;
        if (path.startsWith('/media/')) {
          final mediaId = path.substring('/media/'.length);
          if (request.method == 'PUT') {
            mediaServer.handleUpload(request, mediaId);
          } else {
            request.response
              ..statusCode = HttpStatus.methodNotAllowed
              ..close();
          }
        } else {
          request.response
            ..statusCode = HttpStatus.notFound
            ..close();
        }
      });
    });

    tearDown(() async {
      mediaServer.dispose();
      await testHttpServer.close(force: true);
      await tempDir.delete(recursive: true);
    });

    /// Create a test file with random content and return (file, sha256hex).
    Future<(File, String)> _createTestFile(int size) async {
      final random = Random(42);
      final bytes = List<int>.generate(size, (_) => random.nextInt(256));
      final file = File('${tempDir.path}/test_upload.bin');
      await file.writeAsBytes(bytes);
      final hash = sha256.convert(bytes).toString();
      return (file, hash);
    }

    MediaOffer _makeOffer({
      String id = 'test-media-id',
      String mime = 'image/jpeg',
      int size = 1024,
      String sha256hex = 'abc123',
      String token = 'test-token',
      String nonce = 'test-nonce',
    }) {
      return MediaOffer(
        id: id,
        from: 'senderPeer',
        to: 'receiverPeer',
        mime: mime,
        size: size,
        sha256: sha256hex,
        token: token,
        nonce: nonce,
      );
    }

    Future<HttpClientResponse> _putMedia(
      String mediaId,
      List<int> body, {
      String? authToken,
      String contentType = 'image/jpeg',
    }) async {
      final client = HttpClient();
      try {
        final req = await client.put(
          'localhost',
          serverPort,
          '/media/$mediaId',
        );
        if (authToken != null) {
          req.headers.set('Authorization', 'Bearer $authToken');
        }
        req.headers.contentType = ContentType.parse(contentType);
        req.headers.set('Content-Length', '${body.length}');
        req.add(body);
        return await req.close();
      } finally {
        client.close();
      }
    }

    Future<HttpClientResponse> _putMediaRawPath(
      String rawPath, {
      String? authHeader,
      List<int>? body,
      String contentType = 'image/jpeg',
      int? contentLength,
    }) async {
      final client = HttpClient();
      try {
        final req = await client.openUrl(
          'PUT',
          Uri.parse('http://localhost:$serverPort$rawPath'),
        );
        if (authHeader != null) {
          req.headers.set('Authorization', authHeader);
        }
        req.headers.contentType = ContentType.parse(contentType);
        if (contentLength != null) {
          req.headers.set('Content-Length', '$contentLength');
        } else if (body != null) {
          req.headers.set('Content-Length', '${body.length}');
        }
        if (body != null) {
          req.add(body);
        }
        return await req.close();
      } finally {
        client.close();
      }
    }

    Future<File> _createZeroFile(int size) async {
      final file = File('${tempDir.path}/zero_file_$size.bin');
      final sink = file.openWrite();
      const chunkSize = 64 * 1024;
      final chunk = List<int>.filled(chunkSize, 0);
      var remaining = size;
      while (remaining > 0) {
        final writeLen = remaining > chunkSize ? chunkSize : remaining;
        sink.add(writeLen == chunkSize ? chunk : List<int>.filled(writeLen, 0));
        remaining -= writeLen;
      }
      await sink.flush();
      await sink.close();
      return file;
    }

    Future<String> _sha256OfFile(File file) async {
      late Digest digest;
      final digestSink = _CallbackSink<Digest>((d) => digest = d);
      final hashSink = sha256.startChunkedConversion(digestSink);
      await for (final chunk in file.openRead()) {
        hashSink.add(chunk);
      }
      hashSink.close();
      return digest.toString();
    }

    Future<HttpClientResponse> _putMediaFromFile(
      String mediaId,
      File file, {
      required String authToken,
      String contentType = 'application/octet-stream',
    }) async {
      final client = HttpClient();
      try {
        final req = await client.openUrl(
          'PUT',
          Uri.parse('http://localhost:$serverPort/media/$mediaId'),
        );
        req.headers.set('Authorization', 'Bearer $authToken');
        req.headers.contentType = ContentType.parse(contentType);
        req.headers.set('Content-Length', '${await file.length()}');
        await req.addStream(file.openRead());
        return await req.close();
      } finally {
        client.close();
      }
    }

    group('acceptOffer', () {
      test('accepts valid offer with allowed MIME and size under limit', () {
        final offer = _makeOffer(mime: 'image/jpeg', size: 1024);
        expect(mediaServer.acceptOffer(offer), isTrue);
        expect(mediaServer.hasPendingOffer('test-media-id'), isTrue);
      });

      test('rejects offer with disallowed MIME type', () {
        final offer = _makeOffer(mime: 'text/html', size: 1024);
        expect(mediaServer.acceptOffer(offer), isFalse);
      });

      test('rejects offer exceeding the configured max size', () {
        final offer = _makeOffer(size: LocalMediaServer.maxFileSize + 1);
        expect(mediaServer.acceptOffer(offer), isFalse);
      });

      test('rejects offer with zero size', () {
        final offer = _makeOffer(size: 0);
        expect(mediaServer.acceptOffer(offer), isFalse);
      });

      test('rejects offer with negative size', () {
        final offer = _makeOffer(size: -1);
        expect(mediaServer.acceptOffer(offer), isFalse);
      });

      test('rejects duplicate offer ID', () {
        final offer1 = _makeOffer(id: 'dup-id');
        final offer2 = _makeOffer(id: 'dup-id');
        expect(mediaServer.acceptOffer(offer1), isTrue);
        expect(mediaServer.acceptOffer(offer2), isFalse);
      });

      test('accepts all allowed MIME prefixes', () {
        for (final mime in [
          'image/jpeg',
          'image/png',
          'image/gif',
          'video/mp4',
          'audio/aac',
          'application/pdf',
        ]) {
          final offer = _makeOffer(id: 'id-$mime', mime: mime);
          expect(
            mediaServer.acceptOffer(offer),
            isTrue,
            reason: '$mime should be accepted',
          );
        }
      });
    });

    group('handleUpload (PUT /media/<id>)', () {
      test('rejects PUT without Authorization header → 401', () async {
        final offer = _makeOffer();
        mediaServer.acceptOffer(offer);

        final response = await _putMedia('test-media-id', [1, 2, 3]);
        expect(response.statusCode, HttpStatus.unauthorized);
        await response.drain<void>();
      });

      test('rejects PUT with wrong token → 403', () async {
        final offer = _makeOffer(token: 'correct-token');
        mediaServer.acceptOffer(offer);

        final response = await _putMedia('test-media-id', [
          1,
          2,
          3,
        ], authToken: 'wrong-token');
        expect(response.statusCode, HttpStatus.forbidden);
        await response.drain<void>();
      });

      test('rejects PUT for unknown media ID (no prior offer) → 404', () async {
        final response = await _putMedia('unknown-id', [
          1,
          2,
          3,
        ], authToken: 'any-token');
        expect(response.statusCode, HttpStatus.notFound);
        await response.drain<void>();
      });

      test('rejects concurrent PUT for same ID → 409', () async {
        // Create a large enough file that the first upload takes time.
        final size = 64 * 1024; // 64KB
        final (file, hash) = await _createTestFile(size);
        final bytes = await file.readAsBytes();

        final offer = _makeOffer(
          size: size,
          sha256hex: hash,
          token: 'the-token',
        );
        mediaServer.acceptOffer(offer);

        // Start first upload (don't await immediately).
        final firstUpload = _putMedia(
          'test-media-id',
          bytes,
          authToken: 'the-token',
        );

        // Give the first upload a moment to begin.
        await Future.delayed(const Duration(milliseconds: 10));

        // Second upload should get 409.
        final response2 = await _putMedia(
          'test-media-id',
          bytes,
          authToken: 'the-token',
        );
        expect(response2.statusCode, HttpStatus.conflict);
        await response2.drain<void>();

        // First upload should still complete successfully.
        final response1 = await firstUpload;
        expect(response1.statusCode, HttpStatus.ok);
        await response1.drain<void>();
      });

      test('accepts PUT with valid token, streams to disk', () async {
        const size = 1024;
        final (file, hash) = await _createTestFile(size);
        final bytes = await file.readAsBytes();

        final offer = _makeOffer(
          size: size,
          sha256hex: hash,
          token: 'valid-token',
        );
        mediaServer.acceptOffer(offer);

        final mediaReadyEvents = <LocalMediaReady>[];
        final sub = mediaServer.mediaReadyStream.listen(mediaReadyEvents.add);

        final response = await _putMedia(
          'test-media-id',
          bytes,
          authToken: 'valid-token',
        );
        expect(response.statusCode, HttpStatus.ok);
        await response.drain<void>();

        // Give stream time to propagate.
        await Future.delayed(const Duration(milliseconds: 50));

        expect(mediaReadyEvents, hasLength(1));
        expect(mediaReadyEvents.first.id, 'test-media-id');
        expect(mediaReadyEvents.first.sha256, hash);
        expect(mediaReadyEvents.first.size, size);
        expect(mediaReadyEvents.first.mime, 'image/jpeg');

        // Verify file exists on disk.
        final savedFile = File(mediaReadyEvents.first.localPath);
        expect(await savedFile.exists(), isTrue);
        expect(await savedFile.length(), size);

        await sub.cancel();
      });

      test('verifies SHA-256 after upload, returns success', () async {
        const size = 512;
        final (file, hash) = await _createTestFile(size);
        final bytes = await file.readAsBytes();

        final offer = _makeOffer(size: size, sha256hex: hash, token: 'token');
        mediaServer.acceptOffer(offer);

        final response = await _putMedia(
          'test-media-id',
          bytes,
          authToken: 'token',
        );
        expect(response.statusCode, HttpStatus.ok);
        await response.drain<void>();
      });

      test('rejects upload when SHA-256 mismatch, deletes temp file', () async {
        const size = 512;
        final bytes = List<int>.generate(size, (i) => i % 256);

        final offer = _makeOffer(
          size: size,
          sha256hex: 'definitely-wrong-hash',
          token: 'token',
        );
        mediaServer.acceptOffer(offer);

        final response = await _putMedia(
          'test-media-id',
          bytes,
          authToken: 'token',
        );
        expect(response.statusCode, HttpStatus.badRequest);
        await response.drain<void>();

        // Verify temp file was deleted.
        final tempFile = File('${tempDir.path}/temp/test-media-id.jpg');
        expect(await tempFile.exists(), isFalse);
      });

      test('rejects upload when bytes exceed declared size', () async {
        final offer = _makeOffer(
          size: 10, // Declared 10 bytes
          sha256hex: 'irrelevant',
          token: 'token',
        );
        mediaServer.acceptOffer(offer);

        // Send 100 bytes (way more than declared 10).
        final response = await _putMedia(
          'test-media-id',
          List<int>.filled(100, 42),
          authToken: 'token',
        );
        expect(response.statusCode, HttpStatus.requestEntityTooLarge);
        await response.drain<void>();
      });

      test('rejects upload when body is shorter than declared size', () async {
        final body = [1, 2, 3, 4, 5];
        final offer = _makeOffer(
          size: 10, // Declared larger than actual body.
          sha256hex: sha256.convert(body).toString(),
          token: 'token',
        );
        mediaServer.acceptOffer(offer);

        final response = await _putMedia(
          'test-media-id',
          body,
          authToken: 'token',
        );
        expect(response.statusCode, HttpStatus.badRequest);
        await response.drain<void>();
      });
    });

    group('persistMedia', () {
      test('moves temp file to permanent location', () async {
        const size = 256;
        final (file, hash) = await _createTestFile(size);
        final bytes = await file.readAsBytes();

        final offer = _makeOffer(size: size, sha256hex: hash, token: 'token');
        mediaServer.acceptOffer(offer);

        final response = await _putMedia(
          'test-media-id',
          bytes,
          authToken: 'token',
        );
        expect(response.statusCode, HttpStatus.ok);
        await response.drain<void>();

        final destPath = await mediaServer.persistMedia(
          'test-media-id',
          'contact123',
        );
        expect(destPath, isNotNull);
        expect(await File(destPath!).exists(), isTrue);
        expect(await File(destPath).length(), size);

        // Original temp file should be gone (renamed).
        final tempFile = File('${tempDir.path}/temp/test-media-id.jpg');
        expect(await tempFile.exists(), isFalse);
      });
    });

    group('cleanup', () {
      test('cleanupMedia deletes temp file and removes pending', () async {
        const size = 128;
        final offer = _makeOffer(size: size, sha256hex: 'irrelevant');
        mediaServer.acceptOffer(offer);

        // Create temp dir + file manually to simulate partial state.
        await Directory('${tempDir.path}/temp').create(recursive: true);
        await File(
          '${tempDir.path}/temp/test-media-id.jpg',
        ).writeAsBytes([1, 2, 3]);

        mediaServer.cleanupMedia('test-media-id');
        expect(mediaServer.hasPendingOffer('test-media-id'), isFalse);
        expect(
          await File('${tempDir.path}/temp/test-media-id.jpg').exists(),
          isFalse,
        );
      });

      test('completed files are NOT deleted by cleanup', () async {
        const size = 256;
        final (file, hash) = await _createTestFile(size);
        final bytes = await file.readAsBytes();

        final offer = _makeOffer(size: size, sha256hex: hash, token: 'token');
        mediaServer.acceptOffer(offer);

        final response = await _putMedia(
          'test-media-id',
          bytes,
          authToken: 'token',
        );
        expect(response.statusCode, HttpStatus.ok);
        await response.drain<void>();

        final destPath = await mediaServer.persistMedia(
          'test-media-id',
          'contact',
        );
        expect(destPath, isNotNull);

        // cleanupMedia should be a no-op for persisted files.
        mediaServer.cleanupMedia('test-media-id');
        expect(await File(destPath!).exists(), isTrue);
      });
    });

    group('HTTP method validation', () {
      test('GET /media/<id> returns 405 Method Not Allowed', () async {
        final client = HttpClient();
        try {
          final req = await client.get(
            'localhost',
            serverPort,
            '/media/test-id',
          );
          final response = await req.close();
          expect(response.statusCode, HttpStatus.methodNotAllowed);
          await response.drain<void>();
        } finally {
          client.close();
        }
      });
    });

    group('security and boundary', () {
      test('rejects path traversal mediaId in upload route', () async {
        final response = await _putMediaRawPath(
          '/media/%2E%2E%2Fevil',
          authHeader: 'Bearer token',
          body: [1, 2, 3],
          contentLength: 3,
        );

        expect(response.statusCode, HttpStatus.badRequest);
        await response.drain<void>();
      });

      test('persistMedia rejects path traversal contactPeerId', () async {
        const size = 64;
        final (file, hash) = await _createTestFile(size);
        final bytes = await file.readAsBytes();

        final offer = _makeOffer(
          id: 'persist-traversal',
          size: size,
          sha256hex: hash,
          token: 'token',
        );
        expect(mediaServer.acceptOffer(offer), isTrue);

        final response = await _putMedia(
          'persist-traversal',
          bytes,
          authToken: 'token',
        );
        expect(response.statusCode, HttpStatus.ok);
        await response.drain<void>();

        final result = await mediaServer.persistMedia(
          'persist-traversal',
          '../escape',
        );
        expect(result, isNull);

        // Upload remains pending/temp since persist was rejected.
        final tempFile = File('${tempDir.path}/temp/persist-traversal.jpg');
        expect(await tempFile.exists(), isTrue);
      });

      test('rejects malformed Authorization header variants', () async {
        final offer = _makeOffer(
          id: 'auth-variants',
          size: 3,
          sha256hex: sha256.convert([1, 2, 3]).toString(),
          token: 'token123',
        );
        mediaServer.acceptOffer(offer);

        for (final header in ['bearer token123', 'Bearer  token123']) {
          final response = await _putMediaRawPath(
            '/media/auth-variants',
            authHeader: header,
            body: [1, 2, 3],
            contentLength: 3,
          );
          expect(response.statusCode, HttpStatus.forbidden);
          await response.drain<void>();
        }
      });

      test('production maxFileSize constant is 5GB', () {
        expect(LocalMediaServer.maxFileSize, 5 * 1024 * 1024 * 1024);
      });

      test(
        'accepts upload exactly at the configured max size (streamed)',
        () async {
          mediaServer.dispose();
          mediaServer = _createMediaServer(
            maxAcceptedFileSizeBytes: 512 * 1024,
          );

          final maxSize = mediaServer.maxAcceptedFileSizeBytes;
          final file = await _createZeroFile(maxSize);
          final hash = await _sha256OfFile(file);

          final offer = _makeOffer(
            id: 'max-size',
            size: maxSize,
            sha256hex: hash,
            token: 'max-token',
            mime: 'application/pdf',
          );
          expect(mediaServer.acceptOffer(offer), isTrue);

          final response = await _putMediaFromFile(
            'max-size',
            file,
            authToken: 'max-token',
            contentType: 'application/pdf',
          );
          expect(response.statusCode, HttpStatus.ok);
          await response.drain<void>();
        },
        timeout: const Timeout(Duration(seconds: 120)),
      );
    });

    // --- 112 Phase 1.5: enc-flagged LAN offers stage ciphertext ---
    // Receiver capability ships in build N (the rollout floor) so the
    // Phase-4 LAN sender flip can be held behind the same floor as relay.
    group('enc-flagged offers', () {
      test(
        'enc-flagged upload persists as staged ciphertext artifact, not '
        'promoted to canonical media',
        () async {
          final random = Random(7);
          final bytes = List<int>.generate(1024, (_) => random.nextInt(256));
          final hash = sha256.convert(bytes).toString();
          // Phase-4 senders advertise an opaque mime on enc offers — the
          // receiver must accept it; the real mime travels only inside the
          // encrypted envelope.
          final offer = MediaOffer(
            id: 'enc-blob-1',
            from: 'senderPeer',
            to: 'receiverPeer',
            mime: 'application/octet-stream',
            size: 1024,
            sha256: hash,
            token: 'enc-token',
            nonce: 'enc-nonce',
            enc: true,
            encScheme: 'blob_aes_256_gcm_v1',
          );
          expect(mediaServer.acceptOffer(offer), isTrue);

          final ready = <LocalMediaReady>[];
          final sub = mediaServer.mediaReadyStream.listen(ready.add);
          addTearDown(sub.cancel);

          final response = await _putMedia(
            'enc-blob-1',
            bytes,
            authToken: 'enc-token',
            contentType: 'application/octet-stream',
          );
          expect(response.statusCode, HttpStatus.ok);
          await response.drain<void>();

          final persisted = await mediaServer.persistMedia(
            'enc-blob-1',
            'senderPeer',
          );
          expect(persisted, isNotNull);
          // Staged ciphertext artifact — never a renderable canonical
          // media extension.
          expect(persisted, endsWith('.enc'));
          expect(File(persisted!).existsSync(), isTrue);
          expect(File(persisted).readAsBytesSync(), bytes);

          await Future<void>.delayed(Duration.zero);
          expect(ready, hasLength(1));
          expect(ready.single.enc, isTrue);
          expect(ready.single.encScheme, 'blob_aes_256_gcm_v1');
        },
      );

      test('audio/mp4 maps to .m4a extension', () async {
        final random = Random(9);
        final bytes = List<int>.generate(64, (_) => random.nextInt(256));
        final hash = sha256.convert(bytes).toString();
        final offer = _makeOffer(
          id: 'voice-1',
          mime: 'audio/mp4',
          size: 64,
          sha256hex: hash,
          token: 'voice-token',
        );
        expect(mediaServer.acceptOffer(offer), isTrue);

        final response = await _putMedia(
          'voice-1',
          bytes,
          authToken: 'voice-token',
          contentType: 'audio/mp4',
        );
        expect(response.statusCode, HttpStatus.ok);
        await response.drain<void>();

        final persisted = await mediaServer.persistMedia(
          'voice-1',
          'senderPeer',
        );
        // Voice notes record as audio/mp4 — they must land as .m4a, not the
        // .bin fallback (the voice .bin bug).
        expect(persisted, endsWith('.m4a'));
      });

      test('re-encode-fallback video containers map to playable extensions',
          () async {
        // When the video re-encode falls back to the original container, the
        // real mime is one of these. The staged file must get a playable
        // extension, never the .bin fallback.
        const cases = {
          'video/x-m4v': '.m4v',
          'video/x-msvideo': '.avi',
          'video/x-matroska': '.mkv',
        };
        var index = 0;
        for (final entry in cases.entries) {
          final mime = entry.key;
          final expectedExt = entry.value;
          final id = 'fallback-video-$index';
          index++;
          final random = Random(index + 20);
          final bytes = List<int>.generate(64, (_) => random.nextInt(256));
          final hash = sha256.convert(bytes).toString();
          final offer = _makeOffer(
            id: id,
            mime: mime,
            size: 64,
            sha256hex: hash,
            token: 'token-$id',
          );
          expect(mediaServer.acceptOffer(offer), isTrue);

          final response = await _putMedia(
            id,
            bytes,
            authToken: 'token-$id',
            contentType: mime,
          );
          expect(response.statusCode, HttpStatus.ok);
          await response.drain<void>();

          final persisted = await mediaServer.persistMedia(id, 'senderPeer');
          expect(
            persisted,
            endsWith(expectedExt),
            reason: '$mime should map to $expectedExt, got $persisted',
          );
        }
      });

      test(
        'unflagged legacy plaintext LAN upload still promotes as today',
        () async {
          final random = Random(11);
          final bytes = List<int>.generate(256, (_) => random.nextInt(256));
          final hash = sha256.convert(bytes).toString();
          final offer = _makeOffer(
            id: 'plain-blob-1',
            size: 256,
            sha256hex: hash,
            token: 'plain-token',
          );
          expect(mediaServer.acceptOffer(offer), isTrue);

          final ready = <LocalMediaReady>[];
          final sub = mediaServer.mediaReadyStream.listen(ready.add);
          addTearDown(sub.cancel);

          final response = await _putMedia(
            'plain-blob-1',
            bytes,
            authToken: 'plain-token',
          );
          expect(response.statusCode, HttpStatus.ok);
          await response.drain<void>();

          final persisted = await mediaServer.persistMedia(
            'plain-blob-1',
            'senderPeer',
          );
          expect(persisted, endsWith('.jpg'));
          expect(File(persisted!).readAsBytesSync(), bytes);

          await Future<void>.delayed(Duration.zero);
          expect(ready, hasLength(1));
          expect(ready.single.enc, isFalse);
        },
      );

      test(
        'plaintext offer with disallowed mime is still rejected',
        () async {
          final offer = _makeOffer(
            id: 'plain-octet',
            mime: 'application/octet-stream',
          );
          // The mime whitelist exemption applies ONLY to enc-flagged
          // offers; legacy plaintext offers keep today's validation.
          expect(mediaServer.acceptOffer(offer), isFalse);
        },
      );
    });
  });
}

class _CallbackSink<T> implements Sink<T> {
  final void Function(T) _callback;
  _CallbackSink(this._callback);

  @override
  void add(T data) => _callback(data);

  @override
  void close() {}
}
