import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart';

/// Fake bridge that responds to media:upload commands.
class _FakeBridge implements Bridge {
  Map<String, dynamic> uploadResponse = {'ok': true};
  Map<String, dynamic>? lastRequest;

  @override
  Future<String> send(String message) async {
    lastRequest = jsonDecode(message) as Map<String, dynamic>;
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
}

void main() {
  late _FakeBridge bridge;
  late Directory tempDir;
  late File tempFile;

  setUp(() async {
    bridge = _FakeBridge();
    tempDir = await Directory.systemTemp.createTemp('upload_test_');
    tempFile = File('${tempDir.path}/test_image.jpg');
    await tempFile.writeAsBytes(List.filled(1024, 0xFF)); // 1KB dummy file
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
        expect(result!.mediaType, entry.value,
            reason: 'mediaType for ${entry.key}');
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
    const m = {'image/jpeg': '.jpg', 'image/png': '.png', 'video/mp4': '.mp4', 'audio/mpeg': '.mp3'};
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
}
