import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/group_media_size_policy.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart';

/// Fake bridge that responds to media:upload commands.
class _FakeBridge implements Bridge {
  Map<String, dynamic> uploadResponse = {'ok': true};
  Map<String, dynamic>? lastRequest;
  final List<Map<String, dynamic>> requests = [];
  final List<String> commandLog = [];
  final List<String> generatedKeys = [];
  final Map<String, String> uploadedContentHashes = {};
  int sendCallCount = 0;

  @override
  Future<String> send(String message) async {
    sendCallCount++;
    lastRequest = jsonDecode(message) as Map<String, dynamic>;
    requests.add(lastRequest!);
    final cmd = lastRequest!['cmd'] as String?;
    if (cmd != null) commandLog.add(cmd);
    if (cmd == 'blob:keygen') {
      final key = 'group-test-key-${generatedKeys.length + 1}';
      generatedKeys.add(key);
      return jsonEncode({'ok': true, 'keyBase64': key});
    }
    if (cmd == 'blob:encrypt') {
      final payload = lastRequest!['payload'] as Map<String, dynamic>;
      final sourcePath = payload['filePath'] as String;
      final keyBase64 = payload['keyBase64'] as String;
      final encryptedPath = '$sourcePath.${generatedKeys.length}.enc';
      final sourceBytes = await File(sourcePath).readAsBytes();
      await File(encryptedPath).writeAsBytes([
        ...'cipher:$keyBase64:'.codeUnits,
        ...sourceBytes.reversed,
      ]);
      return jsonEncode({
        'ok': true,
        'encryptedPath': encryptedPath,
        'nonce': 'nonce-${generatedKeys.length}',
      });
    }
    if (cmd == 'media:upload') {
      final payload = lastRequest!['payload'] as Map<String, dynamic>;
      final filePath = payload['filePath'] as String?;
      if (filePath != null && File(filePath).existsSync()) {
        uploadedContentHashes[filePath] =
            await GroupMediaIntegrityPolicy.computeFileSha256Hex(filePath);
      }
    }
    return jsonEncode(uploadResponse);
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
  late Directory tempDir;
  late File tempFile;
  late File gifFile;

  setUp(() async {
    bridge = _FakeBridge();
    tempDir = await Directory.systemTemp.createTemp('upload_test_');
    tempFile = File('${tempDir.path}/test_image.jpg');
    await tempFile.writeAsBytes(List.filled(1024, 0xFF)); // 1KB dummy file
    gifFile = File('${tempDir.path}/test_animation.gif');
    await gifFile.writeAsBytes(List.filled(512, 0x47));
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('uploadMedia', () {
    test('returns MediaAttachment on success', () async {
      final result = await uploadMedia(
        bridge: bridge,
        localFilePath: tempFile.path,
        mime: 'image/jpeg',
        recipientPeerId: '12D3KooWRecipient123',
        width: 1920,
        height: 1080,
      );

      expect(result, isNotNull);
      expect(result!.mime, 'image/jpeg');
      expect(result.size, 1024);
      expect(result.mediaType, 'image');
      expect(result.width, 1920);
      expect(result.height, 1080);
      expect(result.localPath, tempFile.path);
      expect(result.downloadStatus, 'done');
      expect(result.messageId, ''); // set by caller
      expect(result.id, isNotEmpty);
      expect(result.createdAt, isNotEmpty);
      expect(result.contentHash, isNull);
    });

    test('sends correct command to bridge', () async {
      await uploadMedia(
        bridge: bridge,
        localFilePath: tempFile.path,
        mime: 'image/jpeg',
        recipientPeerId: '12D3KooWRecipient123',
      );

      expect(bridge.lastRequest, isNotNull);
      expect(bridge.lastRequest!['cmd'], 'media:upload');
      final payload = bridge.lastRequest!['payload'] as Map<String, dynamic>;
      expect(payload['to'], '12D3KooWRecipient123');
      expect(payload['mime'], 'image/jpeg');
      expect(payload['filePath'], tempFile.path);
      expect(payload['id'], isNotEmpty);
    });

    test('returns null when bridge returns error', () async {
      bridge.uploadResponse = {
        'ok': false,
        'errorCode': 'UPLOAD_FAILED',
        'errorMessage': 'Relay unavailable',
      };

      final result = await uploadMedia(
        bridge: bridge,
        localFilePath: tempFile.path,
        mime: 'image/jpeg',
        recipientPeerId: '12D3KooWRecipient123',
      );

      expect(result, isNull);
    });

    test('returns null when file does not exist', () async {
      final result = await uploadMedia(
        bridge: bridge,
        localFilePath: '/nonexistent/path/file.jpg',
        mime: 'image/jpeg',
        recipientPeerId: '12D3KooWRecipient123',
      );

      expect(result, isNull);
    });

    test('returns null when bridge throws exception', () async {
      final throwBridge = _ThrowingBridge();

      final result = await uploadMedia(
        bridge: throwBridge,
        localFilePath: tempFile.path,
        mime: 'image/jpeg',
        recipientPeerId: '12D3KooWRecipient123',
      );

      expect(result, isNull);
    });

    test(
      'emits MEDIA_UPLOAD_TIMING with blob, mime, and size metadata',
      () async {
        final events = await captureFlowEvents(() async {
          await uploadMedia(
            bridge: bridge,
            localFilePath: tempFile.path,
            mime: 'image/jpeg',
            recipientPeerId: '12D3KooWRecipient123',
          );
        });

        final timing = events.lastWhere(
          (event) => event['event'] == 'MEDIA_UPLOAD_TIMING',
        );
        expect(timing['details']['outcome'], 'success');
        expect(timing['details']['blobId'], isA<String>());
        expect(timing['details']['mime'], 'image/jpeg');
        expect(timing['details']['sizeBytes'], 1024);
        expect(timing['details']['elapsedMs'], isA<int>());
      },
    );

    test('infers mediaType from mime', () async {
      final cases = {
        'video/mp4': 'video',
        'audio/mpeg': 'audio',
        'application/pdf': 'file',
        'image/png': 'image',
      };

      for (final entry in cases.entries) {
        final result = await uploadMedia(
          bridge: bridge,
          localFilePath: tempFile.path,
          mime: entry.key,
          recipientPeerId: 'recipient',
        );
        expect(result, isNotNull, reason: 'Should succeed for ${entry.key}');
        expect(
          result!.mediaType,
          entry.value,
          reason: 'mediaType for ${entry.key}',
        );
      }
    });

    test('passes optional dimensions and duration', () async {
      final result = await uploadMedia(
        bridge: bridge,
        localFilePath: tempFile.path,
        mime: 'video/mp4',
        recipientPeerId: 'recipient',
        width: 1280,
        height: 720,
        durationMs: 30000,
      );

      expect(result, isNotNull);
      expect(result!.width, 1280);
      expect(result.height, 720);
      expect(result.durationMs, 30000);
    });

    test(
      'uploads GIF with mime image/gif and preserves animated metadata',
      () async {
        final result = await uploadMedia(
          bridge: bridge,
          localFilePath: gifFile.path,
          mime: 'image/gif',
          recipientPeerId: 'recipient',
        );

        expect(result, isNotNull);
        expect(result!.mime, 'image/gif');
        expect(result.mediaType, 'image');
        expect(result.isAnimated, isTrue);

        final payload = bridge.lastRequest!['payload'] as Map<String, dynamic>;
        expect(payload['mime'], 'image/gif');
        expect(payload['filePath'], gifFile.path);
      },
    );

    test('rejects dangerous group MIME before bridge upload', () async {
      final result = await uploadMedia(
        bridge: bridge,
        localFilePath: tempFile.path,
        mime: 'application/pdf',
        recipientPeerId: 'group-1',
        allowedPeers: const ['peer-2'],
      );

      expect(result, isNull);
      expect(bridge.sendCallCount, 0);
      expect(bridge.lastRequest, isNull);
    });

    test('group upload computes content hash for uploaded bytes', () async {
      final validJpegFile = File('${tempDir.path}/valid_image.jpg');
      await validJpegFile.writeAsBytes([
        0xff,
        0xd8,
        0xff,
        ...List<int>.filled(1021, 0xff),
      ]);

      final result = await uploadMedia(
        bridge: bridge,
        localFilePath: validJpegFile.path,
        mime: 'image/jpeg',
        recipientPeerId: 'group-1',
        allowedPeers: const ['peer-2'],
      );

      expect(result, isNotNull);
      expect(
        result!.contentHash,
        isNot(
          await GroupMediaIntegrityPolicy.computeFileSha256Hex(
            validJpegFile.path,
          ),
        ),
      );
      final uploadRequest = bridge.requests.lastWhere(
        (request) => request['cmd'] == 'media:upload',
      );
      final uploadPayload = uploadRequest['payload'] as Map<String, dynamic>;
      expect(
        result.contentHash,
        bridge.uploadedContentHashes[uploadPayload['filePath'] as String],
      );
    });

    test(
      'group uploads encrypt each media object with distinct object metadata',
      () async {
        final first = File('${tempDir.path}/first.jpg');
        final second = File('${tempDir.path}/second.jpg');
        await first.writeAsBytes([
          0xff,
          0xd8,
          0xff,
          ...List<int>.filled(32, 0x11),
        ]);
        await second.writeAsBytes([
          0xff,
          0xd8,
          0xff,
          ...List<int>.filled(32, 0x22),
        ]);

        final firstResult = await uploadMedia(
          bridge: bridge,
          localFilePath: first.path,
          mime: 'image/jpeg',
          recipientPeerId: 'group-1',
          allowedPeers: const ['peer-2'],
        );
        final secondResult = await uploadMedia(
          bridge: bridge,
          localFilePath: second.path,
          mime: 'image/jpeg',
          recipientPeerId: 'group-1',
          allowedPeers: const ['peer-2'],
        );

        expect(firstResult, isNotNull);
        expect(secondResult, isNotNull);
        expect(
          bridge.commandLog,
          containsAllInOrder([
            'blob:keygen',
            'blob:encrypt',
            'media:upload',
            'blob:keygen',
            'blob:encrypt',
            'media:upload',
          ]),
        );

        final uploadRequests = bridge.requests
            .where((request) => request['cmd'] == 'media:upload')
            .toList(growable: false);
        expect(uploadRequests, hasLength(2));
        final firstUpload =
            uploadRequests[0]['payload'] as Map<String, dynamic>;
        final secondUpload =
            uploadRequests[1]['payload'] as Map<String, dynamic>;
        expect(firstUpload['filePath'], isNot(first.path));
        expect(secondUpload['filePath'], isNot(second.path));
        expect(firstUpload['filePath'], endsWith('.enc'));
        expect(secondUpload['filePath'], endsWith('.enc'));
        expect(firstResult!.encryptionKeyBase64, isNotNull);
        expect(secondResult!.encryptionKeyBase64, isNotNull);
        expect(
          firstResult.encryptionKeyBase64,
          isNot(secondResult.encryptionKeyBase64),
        );
        expect(firstResult.encryptionNonce, isNotNull);
        expect(secondResult.encryptionNonce, isNotNull);
        expect(
          firstResult.encryptionNonce,
          isNot(secondResult.encryptionNonce),
        );
        expect(firstResult.contentHash, isNot(secondResult.contentHash));
      },
    );

    test('rejects spoofed group media bytes before bridge upload', () async {
      final spoofedFile = File('${tempDir.path}/spoofed.jpg')
        ..writeAsStringSync('<script>alert(1)</script>');

      final result = await uploadMedia(
        bridge: bridge,
        localFilePath: spoofedFile.path,
        mime: 'image/jpeg',
        recipientPeerId: 'group-1',
        allowedPeers: const ['peer-2'],
      );

      expect(result, isNull);
      expect(bridge.sendCallCount, 0);
      expect(bridge.lastRequest, isNull);
    });

    test('rejects oversized group upload before bridge upload', () async {
      final oversizedFile = File('${tempDir.path}/oversized.jpg')
        ..writeAsBytesSync(List.filled(1024, 0x01));

      final result = await uploadMedia(
        bridge: bridge,
        localFilePath: oversizedFile.path,
        mime: 'image/jpeg',
        recipientPeerId: 'group-1',
        allowedPeers: const ['peer-2'],
        groupMediaPerAttachmentLimitBytes: 512,
      );

      expect(result, isNull);
      expect(bridge.sendCallCount, 0);
      expect(bridge.lastRequest, isNull);

      final boundaryResult = await GroupMediaSizePolicy.validateLocalFile(
        path: oversizedFile.path,
        mime: 'image/jpeg',
        perMediaLimitBytes: 1024,
      );
      expect(boundaryResult.isValid, isTrue);
    });

    test('null dimensions when not provided', () async {
      final result = await uploadMedia(
        bridge: bridge,
        localFilePath: tempFile.path,
        mime: 'audio/mpeg',
        recipientPeerId: 'recipient',
      );

      expect(result, isNotNull);
      expect(result!.width, isNull);
      expect(result.height, isNull);
      expect(result.durationMs, isNull);
    });

    group('with mediaFileManager', () {
      late _FakeMediaFileManager fakeFileManager;

      setUp(() {
        fakeFileManager = _FakeMediaFileManager(tempDir.path);
      });

      test('returns relative path in localPath for DB storage', () async {
        final result = await uploadMedia(
          bridge: bridge,
          localFilePath: tempFile.path,
          mime: 'image/jpeg',
          recipientPeerId: 'contact-A',
          mediaFileManager: fakeFileManager,
        );

        expect(result, isNotNull);
        // localPath should be relative (for DB storage)
        expect(result!.localPath, startsWith('media/'));
        expect(result.localPath, contains('contact-A'));
        expect(result.localPath, endsWith('.jpg'));
        // Should NOT be an absolute path
        expect(result.localPath, isNot(startsWith('/')));
      });

      test('copies file to persistent absolute path', () async {
        final result = await uploadMedia(
          bridge: bridge,
          localFilePath: tempFile.path,
          mime: 'image/jpeg',
          recipientPeerId: 'contact-A',
          mediaFileManager: fakeFileManager,
        );

        expect(result, isNotNull);
        // The file should be copied to the absolute path
        final absolutePath = '${tempDir.path}/contact-A/${result!.id}.jpg';
        expect(await File(absolutePath).exists(), isTrue);
        expect(await File(absolutePath).length(), 1024);
      });

      test('without mediaFileManager returns original absolute path', () async {
        final result = await uploadMedia(
          bridge: bridge,
          localFilePath: tempFile.path,
          mime: 'image/jpeg',
          recipientPeerId: 'contact-A',
        );

        expect(result, isNotNull);
        // Without mediaFileManager, localPath is the original file path
        expect(result!.localPath, tempFile.path);
      });
    });
  });
}

/// Fake media file manager that uses a temp directory as base path.
class _FakeMediaFileManager extends MediaFileManager {
  final String basePath;

  _FakeMediaFileManager(this.basePath);

  @override
  Future<String> localPathForAttachment({
    required String contactPeerId,
    required String blobId,
    required String mime,
  }) async {
    final ext = _extFromMime(mime);
    final dir = Directory('$basePath/$contactPeerId');
    if (!await dir.exists()) await dir.create(recursive: true);
    return '$basePath/$contactPeerId/$blobId$ext';
  }

  static String _extFromMime(String mime) {
    const m = {
      'image/jpeg': '.jpg',
      'image/png': '.png',
      'image/gif': '.gif',
      'video/mp4': '.mp4',
      'audio/mpeg': '.mp3',
    };
    return m[mime] ?? '';
  }
}

class _ThrowingBridge implements Bridge {
  @override
  Future<String> send(String message) async =>
      throw Exception('Bridge exploded');
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
