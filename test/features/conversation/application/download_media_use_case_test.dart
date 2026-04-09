import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/application/download_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart';

/// Fake bridge that responds to media:download commands.
class _FakeBridge implements Bridge {
  Map<String, dynamic> downloadResponse = {'ok': true};
  Map<String, dynamic>? lastRequest;
  int sendCallCount = 0;
  List<int> downloadedBytes = const <int>[1, 2, 3];
  bool skipFileWrite = false;

  @override
  Future<String> send(String message) async {
    sendCallCount++;
    lastRequest = jsonDecode(message) as Map<String, dynamic>;
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
            ('blob-download-001', 'failed'),
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
