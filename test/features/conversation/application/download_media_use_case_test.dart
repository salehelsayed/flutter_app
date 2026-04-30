import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/group_media_size_policy.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/application/download_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart';

const _jpegBytes = <int>[0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10];
const _jpegHash =
    'fc16d7dcee9cae83ef3923222a81ccd8fe96c9d25fdb7f504d66f1011e0cd870';
const _mediaKey = 'test-media-key';
const _mediaNonce = 'test-media-nonce';

List<int> _encryptedBytes(
  List<int> plaintext, {
  String key = _mediaKey,
  String nonce = _mediaNonce,
}) {
  return [...'cipher:$key:$nonce:'.codeUnits, ...plaintext.reversed];
}

String _hashBytes(List<int> bytes) => sha256.convert(bytes).toString();

MediaAttachment _encryptedGroupAttachment(
  MediaAttachment attachment,
  List<int> plaintext, {
  String key = _mediaKey,
  String nonce = _mediaNonce,
  String? contentHash,
}) {
  return attachment.copyWith(
    size: plaintext.length,
    contentHash: contentHash ?? _hashBytes(_encryptedBytes(plaintext)),
    encryptionKeyBase64: key,
    encryptionNonce: nonce,
    encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
  );
}

/// Fake bridge that responds to media:download commands.
class _FakeBridge implements Bridge {
  Map<String, dynamic> downloadResponse = {'ok': true};
  Map<String, dynamic>? lastRequest;
  int sendCallCount = 0;
  List<int> downloadedBytes = const <int>[1, 2, 3];
  bool skipFileWrite = false;
  Map<String, dynamic>? decryptResponse;

  @override
  Future<String> send(String message) async {
    sendCallCount++;
    lastRequest = jsonDecode(message) as Map<String, dynamic>;
    final cmd = lastRequest?['cmd'] as String?;
    if (cmd == 'blob:decrypt') {
      if (decryptResponse != null) {
        return jsonEncode(decryptResponse);
      }
      final payload = lastRequest?['payload'] as Map<String, dynamic>?;
      final filePath = payload?['filePath'] as String?;
      final keyBase64 = payload?['keyBase64'] as String?;
      final nonce = payload?['nonce'] as String?;
      if (filePath == null || keyBase64 == null || nonce == null) {
        return jsonEncode({'ok': false, 'errorMessage': 'bad decrypt request'});
      }
      final encrypted = await File(filePath).readAsBytes();
      final prefix = 'cipher:$keyBase64:$nonce:'.codeUnits;
      final hasPrefix =
          encrypted.length >= prefix.length &&
          List.generate(
            prefix.length,
            (index) => encrypted[index] == prefix[index],
          ).every((matches) => matches);
      if (!hasPrefix) {
        return jsonEncode({'ok': false, 'errorMessage': 'decrypt failed'});
      }
      final decryptedPath = '$filePath.dec';
      await File(decryptedPath).writeAsBytes(
        encrypted.skip(prefix.length).toList().reversed.toList(),
        flush: true,
      );
      return jsonEncode({'ok': true, 'decryptedPath': decryptedPath});
    }
    final payload = lastRequest?['payload'] as Map<String, dynamic>?;
    final outputPath = payload?['outputPath'] as String?;
    if (!skipFileWrite &&
        outputPath != null &&
        downloadResponse['ok'] == true) {
      final file = File(outputPath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(downloadedBytes, flush: true);
    }
    return jsonEncode(downloadResponse);
  }

  @override
  Future<void> initialize() async {}
  @override
  Future<bool> checkHealth() async => true;
  @override
  Future<void> reinitialize() async {}
  @override
  void dispose() {}
  @override
  bool get isInitialized => true;
  @override
  void Function(ChatMessage)? onMessageReceived;
  @override
  void Function(ConnectionState)? onPeerConnected;
  @override
  void Function(ConnectionState)? onPeerDisconnected;
  @override
  void Function(List<String> listenAddresses, List<String> circuitAddresses)?
  onAddressesUpdated;
  @override
  void Function(Map<String, dynamic>)? onRelayStateChanged;
  @override
  void Function(Map<String, dynamic>)? onGroupMessageReceived;
  @override
  void Function(Map<String, dynamic>)? onGroupReactionReceived;
}

class _DelayedBridge extends _FakeBridge {
  final Completer<void> gate = Completer<void>();

  @override
  Future<String> send(String message) async {
    sendCallCount++;
    lastRequest = jsonDecode(message) as Map<String, dynamic>;
    await gate.future;
    final payload = lastRequest?['payload'] as Map<String, dynamic>?;
    final outputPath = payload?['outputPath'] as String?;
    if (!skipFileWrite &&
        outputPath != null &&
        downloadResponse['ok'] == true) {
      final file = File(outputPath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(downloadedBytes, flush: true);
    }
    return jsonEncode(downloadResponse);
  }
}

/// Fake media attachment repository that tracks calls.
class _FakeMediaAttachmentRepo implements MediaAttachmentRepository {
  final List<(String, String)> downloadStatusUpdates = [];
  final List<(String, String)> localPathUpdates = [];

  @override
  Future<void> saveAttachment(MediaAttachment attachment) async {}

  @override
  Future<List<MediaAttachment>> getAttachmentsForMessage(
    String messageId,
  ) async => [];

  @override
  Future<Map<String, List<MediaAttachment>>> getAttachmentsForMessages(
    List<String> messageIds,
  ) async => {};

  @override
  Future<void> updateLocalPath(String id, String localPath) async {
    localPathUpdates.add((id, localPath));
  }

  @override
  Future<void> updateDownloadStatus(String id, String downloadStatus) async {
    downloadStatusUpdates.add((id, downloadStatus));
  }

  @override
  Future<int> deleteAttachmentsForMessage(String messageId) async => 0;

  @override
  Future<int> deleteAttachmentsForContact(String contactPeerId) async => 0;

  @override
  Future<int> markUploadPendingAttachmentsFailedForMessage(
    String messageId,
  ) async => 0;

  @override
  Future<List<MediaAttachment>> getPendingDownloads() async => [];

  @override
  Future<List<MediaAttachment>> getUploadPendingAttachments() async => [];
}

/// Fake media file manager that returns a temp-dir-based path.
class _FakeMediaFileManager extends MediaFileManager {
  final String basePath;

  _FakeMediaFileManager(this.basePath);

  @override
  Future<String> localPathForAttachment({
    required String contactPeerId,
    required String blobId,
    required String mime,
  }) async {
    // Simple path without needing path_provider
    final ext = _extensionFromMime(mime);
    return '$basePath/$contactPeerId/$blobId$ext';
  }

  static String _extensionFromMime(String mime) {
    const mimeToExt = {
      'image/jpeg': '.jpg',
      'image/png': '.png',
      'video/mp4': '.mp4',
      'audio/mpeg': '.mp3',
    };
    return mimeToExt[mime] ?? '';
  }

  @override
  Future<void> deleteMediaForContact(String contactPeerId) async {}

  @override
  Future<void> deleteFile(String localPath) async {
    final file = File(localPath);
    if (await file.exists()) {
      await file.delete();
    }
  }
}

Future<List<Map<String, dynamic>>> captureFlowEvents(
  Future<void> Function() action,
) async {
  final printed = <String>[];
  final previousLogging = flowEventLoggingEnabled;
  final originalDebugPrint = debugPrint;
  flowEventLoggingEnabled = true;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) {
      printed.add(message);
    }
  };
  try {
    await action();
  } finally {
    debugPrint = originalDebugPrint;
    flowEventLoggingEnabled = previousLogging;
  }

  return printed
      .where((line) => line.startsWith('[FLOW] '))
      .map(
        (line) =>
            jsonDecode(line.substring('[FLOW] '.length))
                as Map<String, dynamic>,
      )
      .toList();
}

void main() {
  late _FakeBridge bridge;
  late _FakeMediaAttachmentRepo mediaRepo;
  late _FakeMediaFileManager fileManager;
  late Directory tempDir;

  const testAttachment = MediaAttachment(
    id: 'blob-download-001',
    messageId: 'msg-001',
    mime: 'image/jpeg',
    size: 245000,
    mediaType: 'image',
    width: 1920,
    height: 1080,
    downloadStatus: 'pending',
    createdAt: '2026-02-20T10:00:00.000Z',
  );

  setUp(() async {
    bridge = _FakeBridge();
    mediaRepo = _FakeMediaAttachmentRepo();
    tempDir = await Directory.systemTemp.createTemp('download_test_');
    fileManager = _FakeMediaFileManager(tempDir.path);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('downloadMedia', () {
    test('returns updated attachment on success', () async {
      final result = await downloadMedia(
        bridge: bridge,
        mediaAttachmentRepo: mediaRepo,
        mediaFileManager: fileManager,
        attachment: testAttachment,
        contactPeerId: 'contact-A',
      );

      expect(result, isNotNull);
      expect(result!.id, 'blob-download-001');
      expect(result.downloadStatus, 'done');
      expect(result.localPath, isNotNull);
      expect(result.localPath, contains('contact-A'));
      expect(result.localPath, contains('blob-download-001'));
      expect(result.localPath, endsWith('.jpg'));
    });

    test('sends correct command to bridge', () async {
      await downloadMedia(
        bridge: bridge,
        mediaAttachmentRepo: mediaRepo,
        mediaFileManager: fileManager,
        attachment: testAttachment,
        contactPeerId: 'contact-A',
      );

      expect(bridge.lastRequest, isNotNull);
      expect(bridge.lastRequest!['cmd'], 'media:download');
      final payload = bridge.lastRequest!['payload'] as Map<String, dynamic>;
      expect(payload['id'], 'blob-download-001');
      expect(payload['outputPath'], isNotEmpty);
    });

    test('transitions status: pending → downloading → done', () async {
      await downloadMedia(
        bridge: bridge,
        mediaAttachmentRepo: mediaRepo,
        mediaFileManager: fileManager,
        attachment: testAttachment,
        contactPeerId: 'contact-A',
      );

      // Step 1: set to downloading
      expect(mediaRepo.downloadStatusUpdates.length, 1);
      expect(mediaRepo.downloadStatusUpdates[0].$1, 'blob-download-001');
      expect(mediaRepo.downloadStatusUpdates[0].$2, 'downloading');

      // Step 2: updateLocalPath (which implicitly sets done)
      expect(mediaRepo.localPathUpdates.length, 1);
      expect(mediaRepo.localPathUpdates[0].$1, 'blob-download-001');
      expect(mediaRepo.localPathUpdates[0].$2, contains('.jpg'));
    });

    test('stores relative path in DB for persistence', () async {
      await downloadMedia(
        bridge: bridge,
        mediaAttachmentRepo: mediaRepo,
        mediaFileManager: fileManager,
        attachment: testAttachment,
        contactPeerId: 'contact-A',
      );

      // Path stored in DB should be relative (starts with media/)
      final storedPath = mediaRepo.localPathUpdates[0].$2;
      expect(storedPath, startsWith('media/'));
      expect(storedPath, contains('contact-A'));
      expect(storedPath, contains('blob-download-001'));
      expect(storedPath, endsWith('.jpg'));
      // Should NOT be an absolute path
      expect(storedPath, isNot(startsWith('/')));
    });

    test('returns absolute path for immediate UI display', () async {
      final result = await downloadMedia(
        bridge: bridge,
        mediaAttachmentRepo: mediaRepo,
        mediaFileManager: fileManager,
        attachment: testAttachment,
        contactPeerId: 'contact-A',
      );

      // Returned path for UI should be absolute
      expect(result, isNotNull);
      expect(result!.localPath, startsWith('/'));
      expect(result.localPath, contains(tempDir.path));
      expect(result.localPath, contains('contact-A'));
      expect(result.localPath, endsWith('.jpg'));
    });

    test('returns null and sets failed when bridge returns error', () async {
      bridge.downloadResponse = {
        'ok': false,
        'errorCode': 'DOWNLOAD_FAILED',
        'errorMessage': 'Blob not found',
      };

      final result = await downloadMedia(
        bridge: bridge,
        mediaAttachmentRepo: mediaRepo,
        mediaFileManager: fileManager,
        attachment: testAttachment,
        contactPeerId: 'contact-A',
      );

      expect(result, isNull);
      // Status transitions: downloading, then failed
      expect(mediaRepo.downloadStatusUpdates.length, 2);
      expect(mediaRepo.downloadStatusUpdates[0].$2, 'downloading');
      expect(mediaRepo.downloadStatusUpdates[1].$2, 'failed');
    });

    test('returns null and sets failed when bridge throws', () async {
      final throwBridge = _ThrowingBridge();

      final result = await downloadMedia(
        bridge: throwBridge,
        mediaAttachmentRepo: mediaRepo,
        mediaFileManager: fileManager,
        attachment: testAttachment,
        contactPeerId: 'contact-A',
      );

      expect(result, isNull);
      // The downloading status may or may not be set depending on where the
      // exception occurs. The failed status should be set in the catch block.
      expect(
        mediaRepo.downloadStatusUpdates.any((u) => u.$2 == 'failed'),
        isTrue,
      );
    });

    test('preserves original attachment fields in result', () async {
      final result = await downloadMedia(
        bridge: bridge,
        mediaAttachmentRepo: mediaRepo,
        mediaFileManager: fileManager,
        attachment: testAttachment,
        contactPeerId: 'contact-A',
      );

      expect(result, isNotNull);
      expect(result!.messageId, 'msg-001');
      expect(result.mime, 'image/jpeg');
      expect(result.size, 245000);
      expect(result.width, 1920);
      expect(result.height, 1080);
    });

    test(
      'returns null and marks failed when bridge reports success but no file was written',
      () async {
        bridge.skipFileWrite = true;

        final result = await downloadMedia(
          bridge: bridge,
          mediaAttachmentRepo: mediaRepo,
          mediaFileManager: fileManager,
          attachment: testAttachment,
          contactPeerId: 'contact-A',
        );

        expect(result, isNull);
        expect(
          mediaRepo.downloadStatusUpdates,
          equals([
            ('blob-download-001', 'downloading'),
            ('blob-download-001', 'failed'),
          ]),
        );
        expect(mediaRepo.localPathUpdates, isEmpty);
      },
    );

    test(
      'group policy rejects relay-returned MIME mismatch before marking done',
      () async {
        final encrypted = _encryptedBytes(_jpegBytes);
        bridge.downloadedBytes = encrypted;
        bridge.downloadResponse = {
          'ok': true,
          'id': 'blob-download-001',
          'mime': 'text/html',
          'size': encrypted.length,
        };

        final result = await downloadMedia(
          bridge: bridge,
          mediaAttachmentRepo: mediaRepo,
          mediaFileManager: fileManager,
          attachment: _encryptedGroupAttachment(testAttachment, _jpegBytes),
          contactPeerId: 'group-1',
          enforceGroupMediaPolicy: true,
        );

        expect(result, isNull);
        expect(
          mediaRepo.downloadStatusUpdates,
          equals([
            ('blob-download-001', 'downloading'),
            ('blob-download-001', kMediaDownloadStatusIntegrityFailed),
          ]),
        );
        expect(mediaRepo.localPathUpdates, isEmpty);
        final outputPath =
            (bridge.lastRequest!['payload']
                    as Map<String, dynamic>)['outputPath']
                as String;
        expect(File(outputPath).existsSync(), isFalse);
      },
    );

    test(
      'group policy rejects oversized declared attachment before media download',
      () async {
        final result = await downloadMedia(
          bridge: bridge,
          mediaAttachmentRepo: mediaRepo,
          mediaFileManager: fileManager,
          attachment: testAttachment.copyWith(
            size: kGroupMediaPerAttachmentLimitBytes + 1,
            contentHash: _hashBytes(_encryptedBytes(_jpegBytes)),
            encryptionKeyBase64: _mediaKey,
            encryptionNonce: _mediaNonce,
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
          ),
          contactPeerId: 'group-1',
          enforceGroupMediaPolicy: true,
        );

        expect(result, isNull);
        expect(bridge.sendCallCount, 0);
        expect(bridge.lastRequest, isNull);
        expect(
          mediaRepo.downloadStatusUpdates,
          equals([('blob-download-001', kMediaDownloadStatusIntegrityFailed)]),
        );
        expect(mediaRepo.localPathUpdates, isEmpty);
      },
    );

    test(
      'group policy rejects spoofed downloaded bytes before marking done',
      () async {
        final spoofedBytes = '<script>alert(1)</script>'.codeUnits;
        final encryptedSpoofedBytes = _encryptedBytes(spoofedBytes);
        bridge.downloadedBytes = encryptedSpoofedBytes;
        bridge.downloadResponse = {
          'ok': true,
          'id': 'blob-download-001',
          'mime': 'image/jpeg',
          'size': encryptedSpoofedBytes.length,
        };

        final result = await downloadMedia(
          bridge: bridge,
          mediaAttachmentRepo: mediaRepo,
          mediaFileManager: fileManager,
          attachment: _encryptedGroupAttachment(testAttachment, spoofedBytes),
          contactPeerId: 'group-1',
          enforceGroupMediaPolicy: true,
        );

        expect(result, isNull);
        expect(
          mediaRepo.downloadStatusUpdates,
          equals([
            ('blob-download-001', 'downloading'),
            ('blob-download-001', kMediaDownloadStatusIntegrityFailed),
          ]),
        );
        expect(mediaRepo.localPathUpdates, isEmpty);
        final outputPath = await fileManager.localPathForAttachment(
          contactPeerId: 'group-1',
          blobId: 'blob-download-001',
          mime: 'image/jpeg',
        );
        expect(File(outputPath).existsSync(), isFalse);
      },
    );

    test('group policy verifies content hash before marking done', () async {
      final encrypted = _encryptedBytes(_jpegBytes);
      bridge.downloadedBytes = encrypted;
      bridge.downloadResponse = {
        'ok': true,
        'id': 'blob-download-001',
        'mime': 'image/jpeg',
        'size': encrypted.length,
      };

      final result = await downloadMedia(
        bridge: bridge,
        mediaAttachmentRepo: mediaRepo,
        mediaFileManager: fileManager,
        attachment: _encryptedGroupAttachment(testAttachment, _jpegBytes),
        contactPeerId: 'group-1',
        enforceGroupMediaPolicy: true,
      );

      expect(result, isNotNull);
      expect(result!.downloadStatus, 'done');
      expect(
        mediaRepo.downloadStatusUpdates,
        equals([('blob-download-001', 'downloading')]),
      );
      expect(mediaRepo.localPathUpdates, hasLength(1));
    });

    test('group policy rejects cross-object decrypt key attempts', () async {
      final encrypted = _encryptedBytes(
        _jpegBytes,
        key: 'object-a-key',
        nonce: 'object-a-nonce',
      );
      bridge.downloadedBytes = encrypted;
      bridge.downloadResponse = {
        'ok': true,
        'id': 'blob-download-001',
        'mime': 'image/jpeg',
        'size': encrypted.length,
      };

      final result = await downloadMedia(
        bridge: bridge,
        mediaAttachmentRepo: mediaRepo,
        mediaFileManager: fileManager,
        attachment: _encryptedGroupAttachment(
          testAttachment,
          _jpegBytes,
          key: 'object-b-key',
          nonce: 'object-b-nonce',
          contentHash: _hashBytes(encrypted),
        ),
        contactPeerId: 'group-1',
        enforceGroupMediaPolicy: true,
      );

      expect(result, isNull);
      expect(
        mediaRepo.downloadStatusUpdates,
        equals([
          ('blob-download-001', 'downloading'),
          ('blob-download-001', kMediaDownloadStatusIntegrityFailed),
        ]),
      );
      expect(mediaRepo.localPathUpdates, isEmpty);
      final outputPath = await fileManager.localPathForAttachment(
        contactPeerId: 'group-1',
        blobId: 'blob-download-001',
        mime: 'image/jpeg',
      );
      expect(File(outputPath).existsSync(), isFalse);
    });

    test(
      'MD-012 missing decrypted file quarantines instead of generic failed',
      () async {
        final encrypted = _encryptedBytes(_jpegBytes);
        bridge.downloadedBytes = encrypted;
        bridge.downloadResponse = {
          'ok': true,
          'id': 'blob-download-001',
          'mime': 'image/jpeg',
          'size': encrypted.length,
        };
        bridge.decryptResponse = {
          'ok': true,
          'decryptedPath': '${tempDir.path}/missing-decrypted.jpg',
        };

        final result = await downloadMedia(
          bridge: bridge,
          mediaAttachmentRepo: mediaRepo,
          mediaFileManager: fileManager,
          attachment: _encryptedGroupAttachment(testAttachment, _jpegBytes),
          contactPeerId: 'group-1',
          enforceGroupMediaPolicy: true,
        );

        expect(result, isNull);
        expect(
          mediaRepo.downloadStatusUpdates,
          equals([
            ('blob-download-001', 'downloading'),
            ('blob-download-001', kMediaDownloadStatusIntegrityFailed),
          ]),
        );
        expect(mediaRepo.localPathUpdates, isEmpty);
      },
    );

    test(
      'MD-012 plaintext size mismatch quarantines instead of generic failed',
      () async {
        final encrypted = _encryptedBytes(_jpegBytes);
        bridge.downloadedBytes = encrypted;
        bridge.downloadResponse = {
          'ok': true,
          'id': 'blob-download-001',
          'mime': 'image/jpeg',
          'size': encrypted.length,
        };

        final result = await downloadMedia(
          bridge: bridge,
          mediaAttachmentRepo: mediaRepo,
          mediaFileManager: fileManager,
          attachment: _encryptedGroupAttachment(
            testAttachment,
            _jpegBytes,
          ).copyWith(size: _jpegBytes.length + 1),
          contactPeerId: 'group-1',
          enforceGroupMediaPolicy: true,
        );

        expect(result, isNull);
        expect(
          mediaRepo.downloadStatusUpdates,
          equals([
            ('blob-download-001', 'downloading'),
            ('blob-download-001', kMediaDownloadStatusIntegrityFailed),
          ]),
        );
        expect(mediaRepo.localPathUpdates, isEmpty);
      },
    );

    test(
      'group policy deletes mismatched content hash bytes and does not mark done',
      () async {
        final encrypted = _encryptedBytes(_jpegBytes);
        bridge.downloadedBytes = encrypted;
        bridge.downloadResponse = {
          'ok': true,
          'id': 'blob-download-001',
          'mime': 'image/jpeg',
          'size': encrypted.length,
        };

        final result = await downloadMedia(
          bridge: bridge,
          mediaAttachmentRepo: mediaRepo,
          mediaFileManager: fileManager,
          attachment: _encryptedGroupAttachment(
            testAttachment,
            _jpegBytes,
            contentHash:
                'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          ),
          contactPeerId: 'group-1',
          enforceGroupMediaPolicy: true,
        );

        expect(result, isNull);
        expect(
          mediaRepo.downloadStatusUpdates,
          equals([
            ('blob-download-001', 'downloading'),
            ('blob-download-001', kMediaDownloadStatusIntegrityFailed),
          ]),
        );
        expect(mediaRepo.localPathUpdates, isEmpty);
        final outputPath =
            (bridge.lastRequest!['payload']
                    as Map<String, dynamic>)['outputPath']
                as String;
        expect(File(outputPath).existsSync(), isFalse);
      },
    );

    test('group policy rejects missing content hash before download', () async {
      final result = await downloadMedia(
        bridge: bridge,
        mediaAttachmentRepo: mediaRepo,
        mediaFileManager: fileManager,
        attachment: testAttachment,
        contactPeerId: 'group-1',
        enforceGroupMediaPolicy: true,
      );

      expect(result, isNull);
      expect(bridge.sendCallCount, 0);
      expect(
        mediaRepo.downloadStatusUpdates,
        equals([('blob-download-001', kMediaDownloadStatusIntegrityFailed)]),
      );
      expect(mediaRepo.localPathUpdates, isEmpty);
    });

    test(
      'group policy rejects missing encryption metadata before download',
      () async {
        final result = await downloadMedia(
          bridge: bridge,
          mediaAttachmentRepo: mediaRepo,
          mediaFileManager: fileManager,
          attachment: testAttachment.copyWith(contentHash: _jpegHash),
          contactPeerId: 'group-1',
          enforceGroupMediaPolicy: true,
        );

        expect(result, isNull);
        expect(bridge.sendCallCount, 0);
        expect(
          mediaRepo.downloadStatusUpdates,
          equals([('blob-download-001', kMediaDownloadStatusIntegrityFailed)]),
        );
        expect(mediaRepo.localPathUpdates, isEmpty);
      },
    );

    test(
      'emits MEDIA_DOWNLOAD_TIMING with blob, mime, and size metadata',
      () async {
        final events = await captureFlowEvents(() async {
          await downloadMedia(
            bridge: bridge,
            mediaAttachmentRepo: mediaRepo,
            mediaFileManager: fileManager,
            attachment: testAttachment,
            contactPeerId: 'contact-A',
          );
        });

        final timing = events.lastWhere(
          (event) => event['event'] == 'MEDIA_DOWNLOAD_TIMING',
        );
        expect(timing['details']['outcome'], 'success');
        expect(timing['details']['blobId'], 'blob-dow');
        expect(timing['details']['mime'], 'image/jpeg');
        expect(timing['details']['sizeBytes'], 245000);
        expect(timing['details']['elapsedMs'], isA<int>());
      },
    );

    test(
      'overlapping callers for the same attachment trigger only one real download',
      () async {
        final delayedBridge = _DelayedBridge();

        final firstFuture = downloadMedia(
          bridge: delayedBridge,
          mediaAttachmentRepo: mediaRepo,
          mediaFileManager: fileManager,
          attachment: testAttachment,
          contactPeerId: 'contact-A',
        );
        await Future<void>.delayed(Duration.zero);

        final secondFuture = downloadMedia(
          bridge: delayedBridge,
          mediaAttachmentRepo: mediaRepo,
          mediaFileManager: fileManager,
          attachment: testAttachment,
          contactPeerId: 'contact-A',
        );
        await Future<void>.delayed(Duration.zero);

        delayedBridge.gate.complete();
        final results = await Future.wait([firstFuture, secondFuture]);

        expect(delayedBridge.sendCallCount, 1);
        expect(
          mediaRepo.downloadStatusUpdates,
          equals([('blob-download-001', 'downloading')]),
        );
        expect(mediaRepo.localPathUpdates, hasLength(1));
        expect(results[0], isNotNull);
        expect(results[1], isNotNull);
        expect(results[0]!.localPath, results[1]!.localPath);
        expect(results[0]!.downloadStatus, 'done');
        expect(results[1]!.downloadStatus, 'done');
      },
    );

    test(
      'overlapping callers share failed outcome without leaving download state oscillating',
      () async {
        final delayedBridge = _DelayedBridge()
          ..downloadResponse = {
            'ok': false,
            'errorCode': 'DOWNLOAD_FAILED',
            'errorMessage': 'Blob not found',
          };

        final firstFuture = downloadMedia(
          bridge: delayedBridge,
          mediaAttachmentRepo: mediaRepo,
          mediaFileManager: fileManager,
          attachment: testAttachment,
          contactPeerId: 'contact-A',
        );
        await Future<void>.delayed(Duration.zero);

        final secondFuture = downloadMedia(
          bridge: delayedBridge,
          mediaAttachmentRepo: mediaRepo,
          mediaFileManager: fileManager,
          attachment: testAttachment,
          contactPeerId: 'contact-A',
        );
        await Future<void>.delayed(Duration.zero);

        delayedBridge.gate.complete();
        final results = await Future.wait([firstFuture, secondFuture]);

        expect(delayedBridge.sendCallCount, 1);
        expect(results, equals([null, null]));
        expect(
          mediaRepo.downloadStatusUpdates,
          equals([
            ('blob-download-001', 'downloading'),
            ('blob-download-001', kMediaDownloadStatusFailed),
          ]),
        );
        expect(mediaRepo.localPathUpdates, isEmpty);
      },
    );
  });
}

class _ThrowingBridge implements Bridge {
  @override
  Future<String> send(String message) async =>
      throw Exception('Download exploded');
  @override
  Future<void> initialize() async {}
  @override
  Future<bool> checkHealth() async => true;
  @override
  Future<void> reinitialize() async {}
  @override
  void dispose() {}
  @override
  bool get isInitialized => true;
  @override
  void Function(ChatMessage)? onMessageReceived;
  @override
  void Function(ConnectionState)? onPeerConnected;
  @override
  void Function(ConnectionState)? onPeerDisconnected;
  @override
  void Function(List<String> listenAddresses, List<String> circuitAddresses)?
  onAddressesUpdated;
  @override
  void Function(Map<String, dynamic>)? onRelayStateChanged;
  @override
  void Function(Map<String, dynamic>)? onGroupMessageReceived;
  @override
  void Function(Map<String, dynamic>)? onGroupReactionReceived;
}
