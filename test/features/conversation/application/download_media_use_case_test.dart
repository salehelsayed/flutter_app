import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/constants/retry_constants.dart';
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
  bool throwOnDecrypt = false;
  FutureOr<void> Function(Map<String, dynamic> request)? beforeDownloadResponse;

  /// Ordered record of every bridge command received, including media:delete.
  final List<String> commandLog = [];

  // media:delete acks are recorded separately so existing
  // sendCallCount/lastRequest assertions stay focused on media:download.
  final List<Map<String, dynamic>> deleteRequests = [];
  Map<String, dynamic> deleteResponse = {'ok': true};
  bool throwOnDelete = false;
  void Function()? onDeleteRequest;

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    commandLog.add(parsed['cmd'] as String);
    if (parsed['cmd'] == 'media:delete') {
      deleteRequests.add(parsed);
      onDeleteRequest?.call();
      if (throwOnDelete) {
        throw Exception('delete exploded');
      }
      return jsonEncode(deleteResponse);
    }
    sendCallCount++;
    lastRequest = parsed;
    final cmd = lastRequest?['cmd'] as String?;
    if (cmd == 'blob:decrypt') {
      if (throwOnDecrypt) {
        throw TimeoutException('blob:decrypt stalled');
      }
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
    if (cmd == 'media:download') {
      await beforeDownloadResponse?.call(lastRequest!);
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
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    if (parsed['cmd'] == 'media:delete') {
      return super.send(message);
    }
    sendCallCount++;
    lastRequest = parsed;
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

/// Writes the full payload to the .part path, then throws TimeoutException —
/// simulating the Dart watchdog giving up while the native transfer actually
/// completed.
class _TimeoutAfterWriteBridge extends _FakeBridge {
  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    if (parsed['cmd'] == 'media:download') {
      sendCallCount++;
      lastRequest = parsed;
      final payload = parsed['payload'] as Map<String, dynamic>;
      final outputPath = payload['outputPath'] as String;
      final file = File(outputPath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(downloadedBytes, flush: true);
      throw TimeoutException('media:download stalled_no_progress after 0s');
    }
    return super.send(message);
  }
}

class _FailOncePartialDownloadBridge extends _FakeBridge {
  String? firstOutputPath;
  bool _failedOnce = false;

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    if (parsed['cmd'] == 'media:download' && !_failedOnce) {
      sendCallCount++;
      lastRequest = parsed;
      final payload = parsed['payload'] as Map<String, dynamic>;
      final outputPath = payload['outputPath'] as String;
      firstOutputPath = outputPath;
      final file = File(outputPath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(<int>[9, 9], flush: true);
      _failedOnce = true;
      return jsonEncode({
        'ok': false,
        'errorMessage': 'forced partial download failure',
      });
    }
    return super.send(message);
  }
}

/// Fake media attachment repository that tracks calls.
class _FakeMediaAttachmentRepo implements MediaAttachmentRepository {
  final List<(String, String)> downloadStatusUpdates = [];
  final List<(String, String)> localPathUpdates = [];
  final Map<String, List<MediaAttachment>> _attachmentsByMessage = {};

  @override
  Future<void> saveAttachment(
    MediaAttachment attachment, {
    required MediaOwnerLane owner,
  }) async {
    seedAttachment(attachment);
  }

  @override
  Future<List<MediaAttachment>> getAttachmentsForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) async => List<MediaAttachment>.of(
    _attachmentsByMessage[messageId] ?? const <MediaAttachment>[],
  );

  @override
  Future<Map<String, List<MediaAttachment>>> getAttachmentsForMessages(
    List<String> messageIds, {
    required MediaOwnerLane owner,
  }) async => {
    for (final messageId in messageIds)
      if (_attachmentsByMessage.containsKey(messageId))
        messageId: List<MediaAttachment>.of(_attachmentsByMessage[messageId]!),
  };

  @override
  Future<void> updateLocalPath(String id, String localPath) async {
    localPathUpdates.add((id, localPath));
    _updateAttachment(
      id,
      // Mirrors dbUpdateMediaLocalPath: a successful local-path commit resets
      // the bounded download retry budget (INV-DL-2).
      (attachment) => attachment.copyWith(
        localPath: localPath,
        downloadStatus: kMediaDownloadStatusDone,
        downloadRetryCount: 0,
      ),
    );
  }

  @override
  Future<void> updateDownloadStatus(String id, String downloadStatus) async {
    downloadStatusUpdates.add((id, downloadStatus));
    _updateAttachment(
      id,
      (attachment) => attachment.copyWith(downloadStatus: downloadStatus),
    );
  }

  @override
  Future<int> deleteAttachmentsForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) async => 0;

  @override
  Future<int> deleteAttachmentsForContact(String contactPeerId) async => 0;

  @override
  Future<int> markUploadPendingAttachmentsFailedForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) async => 0;

  @override
  Future<List<MediaAttachment>> getPendingDownloads() async => [];

  @override
  Future<List<MediaAttachment>> getUploadPendingAttachments({
    required MediaOwnerLane owner,
  }) async => [];

  void seedAttachment(MediaAttachment attachment) {
    final attachments = _attachmentsByMessage.putIfAbsent(
      attachment.messageId,
      () => <MediaAttachment>[],
    );
    attachments.removeWhere((stored) => stored.id == attachment.id);
    attachments.add(attachment);
  }

  void _updateAttachment(
    String id,
    MediaAttachment Function(MediaAttachment attachment) update,
  ) {
    for (final entry in _attachmentsByMessage.entries) {
      final index = entry.value.indexWhere((attachment) => attachment.id == id);
      if (index == -1) {
        continue;
      }
      entry.value[index] = update(entry.value[index]);
      return;
    }
  }
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
  Future<void> deleteFile(
    String localPath, {
    String caller = 'MediaFileManager.deleteFile',
    String reason = 'media_file_delete',
    String? storedPath,
    Map<String, Object?> details = const {},
  }) async {
    final file = File(localPath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  @override
  Future<String> resolveStoredPath(String storedPath) async {
    if (storedPath.startsWith('/')) {
      return storedPath;
    }
    return '$basePath/$storedPath';
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

Future<void> _waitForCapturedFlowEvent(
  List<Map<String, dynamic>> events,
  String eventName,
) async {
  for (var attempt = 0; attempt < 20; attempt += 1) {
    if (events.any((event) => event['event'] == eventName)) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
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
    debugGroupMediaDownloadPostCommitProbeDelays = const [];
    bridge = _FakeBridge();
    mediaRepo = _FakeMediaAttachmentRepo();
    tempDir = await Directory.systemTemp.createTemp('download_test_');
    fileManager = _FakeMediaFileManager(tempDir.path);
  });

  tearDown(() async {
    debugGroupMediaDownloadPostCommitProbeDelays = const [
      Duration(milliseconds: 250),
      Duration(seconds: 1),
    ];
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('downloadMedia', () {
    test('returns updated attachment on success', () async {
      final result = await downloadMedia(
        owner: MediaOwnerLane.direct,
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
        owner: MediaOwnerLane.direct,
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
        owner: MediaOwnerLane.direct,
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
        owner: MediaOwnerLane.direct,
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
        owner: MediaOwnerLane.direct,
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

    test('sends media:delete for the blob after successful commit', () async {
      final result = await downloadMedia(
        owner: MediaOwnerLane.direct,
        bridge: bridge,
        mediaAttachmentRepo: mediaRepo,
        mediaFileManager: fileManager,
        attachment: testAttachment,
        contactPeerId: 'contact-A',
      );

      expect(result, isNotNull);
      expect(result!.downloadStatus, 'done');
      // Commit happened before the ack
      expect(mediaRepo.localPathUpdates, hasLength(1));

      // Ack is fire-and-forget — give the microtask a beat
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(bridge.deleteRequests, hasLength(1));
      final payload =
          bridge.deleteRequests.single['payload'] as Map<String, dynamic>;
      expect(payload['id'], 'blob-download-001');
    });

    test('media:delete failure does not affect done status', () async {
      bridge.throwOnDelete = true;

      final events = await captureFlowEvents(() async {
        final result = await downloadMedia(
          owner: MediaOwnerLane.direct,
          bridge: bridge,
          mediaAttachmentRepo: mediaRepo,
          mediaFileManager: fileManager,
          attachment: testAttachment,
          contactPeerId: 'contact-A',
        );

        expect(result, isNotNull);
        expect(result!.downloadStatus, 'done');
        // Ack is fire-and-forget — let it run and emit its failure event.
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });

      expect(
        events.any((event) => event['event'] == 'MEDIA_ACK_DELETE_FAILED'),
        isTrue,
      );
      // Status must remain done despite the failed ack
      expect(mediaRepo.localPathUpdates, hasLength(1));
      expect(
        mediaRepo.downloadStatusUpdates.where(
          (update) => update.$2 == 'failed',
        ),
        isEmpty,
      );
    });

    test('no media:delete on failed download', () async {
      bridge.downloadResponse = {
        'ok': false,
        'errorCode': 'DOWNLOAD_FAILED',
        'errorMessage': 'Blob not found',
      };

      final result = await downloadMedia(
        owner: MediaOwnerLane.direct,
        bridge: bridge,
        mediaAttachmentRepo: mediaRepo,
        mediaFileManager: fileManager,
        attachment: testAttachment,
        contactPeerId: 'contact-A',
      );

      expect(result, isNull);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(bridge.deleteRequests, isEmpty);
    });

    test('returns null and sets failed when bridge returns error', () async {
      // A GENERIC transient relay error (NOT "not found"/"not authorized")
      // keeps the row in the bounded `failed` state; the terminal short-circuit
      // for relay-unavailable errors is covered separately below (INV-DL-4).
      bridge.downloadResponse = {
        'ok': false,
        'errorCode': 'DOWNLOAD_FAILED',
        'errorMessage': 'relay temporarily unavailable',
      };

      final result = await downloadMedia(
        owner: MediaOwnerLane.direct,
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

    test('increments download_retry_count on a transient failure and flips to '
        'download_failed at the ceiling (INV-DL-1)', () async {
      bridge.downloadResponse = {
        'ok': false,
        'errorMessage': 'relay temporarily unavailable',
      };

      // First transient failure: count 0 -> 1, still the retryable `failed`.
      await downloadMedia(
        owner: MediaOwnerLane.direct,
        bridge: bridge,
        mediaAttachmentRepo: mediaRepo,
        mediaFileManager: fileManager,
        attachment: testAttachment,
        contactPeerId: 'contact-A',
      );
      var stored = (await mediaRepo.getAttachmentsForMessage(
        owner: MediaOwnerLane.direct,
        'msg-001',
      )).firstWhere((a) => a.id == testAttachment.id);
      expect(stored.downloadStatus, kMediaDownloadStatusFailed);
      expect(stored.downloadRetryCount, 1);

      // One short of the ceiling: the next failure becomes terminal.
      await downloadMedia(
        owner: MediaOwnerLane.direct,
        bridge: bridge,
        mediaAttachmentRepo: mediaRepo,
        mediaFileManager: fileManager,
        attachment: testAttachment.copyWith(
          downloadRetryCount: kMaxDownloadRetries - 1,
        ),
        contactPeerId: 'contact-A',
      );
      stored = (await mediaRepo.getAttachmentsForMessage(
        owner: MediaOwnerLane.direct,
        'msg-001',
      )).firstWhere((a) => a.id == testAttachment.id);
      expect(stored.downloadStatus, kMediaDownloadStatusDownloadFailed);
      expect(stored.downloadRetryCount, kMaxDownloadRetries);
    });

    test('relay not found short-circuits to download_failed without burning the '
        'retry budget (INV-DL-4)', () async {
      bridge.downloadResponse = {'ok': false, 'errorMessage': 'not found'};
      // Seed a partially-used budget; the short-circuit must NOT increment it.
      mediaRepo.seedAttachment(testAttachment.copyWith(downloadRetryCount: 1));

      final result = await downloadMedia(
        owner: MediaOwnerLane.direct,
        bridge: bridge,
        mediaAttachmentRepo: mediaRepo,
        mediaFileManager: fileManager,
        attachment: testAttachment.copyWith(downloadRetryCount: 1),
        contactPeerId: 'contact-A',
      );

      expect(result, isNull);
      final stored = (await mediaRepo.getAttachmentsForMessage(
        owner: MediaOwnerLane.direct,
        'msg-001',
      )).firstWhere((a) => a.id == testAttachment.id);
      expect(stored.downloadStatus, kMediaDownloadStatusDownloadFailed);
      // Budget unchanged: the relay-unavailable terminal burns 0 retries.
      expect(stored.downloadRetryCount, 1);
    });

    test(
      'a successful download resets download_retry_count to 0 (INV-DL-2)',
      () async {
        // Start from a partially-used budget.
        mediaRepo.seedAttachment(
          testAttachment.copyWith(downloadRetryCount: 2),
        );

        final result = await downloadMedia(
          owner: MediaOwnerLane.direct,
          bridge: bridge,
          mediaAttachmentRepo: mediaRepo,
          mediaFileManager: fileManager,
          attachment: testAttachment.copyWith(downloadRetryCount: 2),
          contactPeerId: 'contact-A',
        );

        expect(result, isNotNull);
        expect(result!.downloadStatus, kMediaDownloadStatusDone);
        final stored = (await mediaRepo.getAttachmentsForMessage(
          owner: MediaOwnerLane.direct,
          'msg-001',
        )).firstWhere((a) => a.id == testAttachment.id);
        expect(stored.downloadRetryCount, 0);
      },
    );

    test(
      'repeated transient failures converge to terminal download_failed within '
      'kMaxDownloadRetries (no infinite retry)',
      () async {
        bridge.downloadResponse = {
          'ok': false,
          'errorMessage': 'relay temporarily unavailable',
        };

        // Drive the auto-recovery loop by hand: keep re-downloading while the
        // row is still recoverable, asserting it can never loop forever.
        var attempts = 0;
        var current = testAttachment;
        while (current.downloadStatus == kMediaDownloadStatusPending ||
            GroupMediaIntegrityPolicy.isRetryableDownloadFailure(current)) {
          attempts++;
          expect(
            attempts,
            lessThanOrEqualTo(kMaxDownloadRetries),
            reason: 'bounded retries must converge, never retry forever',
          );
          await downloadMedia(
            owner: MediaOwnerLane.direct,
            bridge: bridge,
            mediaAttachmentRepo: mediaRepo,
            mediaFileManager: fileManager,
            attachment: current,
            contactPeerId: 'contact-A',
          );
          current = (await mediaRepo.getAttachmentsForMessage(
            owner: MediaOwnerLane.direct,
            'msg-001',
          )).firstWhere((a) => a.id == testAttachment.id);
        }

        expect(attempts, kMaxDownloadRetries);
        expect(current.downloadStatus, kMediaDownloadStatusDownloadFailed);
        expect(current.downloadRetryCount, kMaxDownloadRetries);
        expect(
          GroupMediaIntegrityPolicy.isRetryableDownloadFailure(current),
          isFalse,
        );
      },
    );

    test(
      'downloadMedia adopts canonical file before bridge download',
      () async {
        final orphanedAttachment = testAttachment.copyWith(
          size: _jpegBytes.length,
          localPath: null,
          downloadStatus: kMediaDownloadStatusFailed,
        );
        final canonicalPath = await fileManager.localPathForAttachment(
          contactPeerId: 'contact-A',
          blobId: orphanedAttachment.id,
          mime: orphanedAttachment.mime,
        );
        final canonicalFile = File(canonicalPath);
        await canonicalFile.parent.create(recursive: true);
        await canonicalFile.writeAsBytes(_jpegBytes, flush: true);
        bridge.downloadResponse = {
          'ok': false,
          'errorCode': 'DOWNLOAD_FAILED',
          'errorMessage': 'Blob not found',
        };

        final result = await downloadMedia(
          owner: MediaOwnerLane.direct,
          bridge: bridge,
          mediaAttachmentRepo: mediaRepo,
          mediaFileManager: fileManager,
          attachment: orphanedAttachment,
          contactPeerId: 'contact-A',
        );

        expect(result, isNotNull);
        expect(result!.downloadStatus, kMediaDownloadStatusDone);
        expect(result.localPath, canonicalPath);
        expect(bridge.sendCallCount, 0);
        expect(
          mediaRepo.localPathUpdates,
          equals([
            (
              orphanedAttachment.id,
              'media/contact-A/${orphanedAttachment.id}.jpg',
            ),
          ]),
        );
        expect(mediaRepo.downloadStatusUpdates, isEmpty);
        expect(canonicalFile.existsSync(), isTrue);
        expect(canonicalFile.readAsBytesSync(), _jpegBytes);
      },
    );

    test(
      'downloadMedia does not delete pre-existing canonical file when bridge returns not found',
      () async {
        final preExistingBytes = <int>[7, 7];
        final canonicalPath = await fileManager.localPathForAttachment(
          contactPeerId: 'contact-A',
          blobId: testAttachment.id,
          mime: testAttachment.mime,
        );
        final canonicalFile = File(canonicalPath);
        await canonicalFile.parent.create(recursive: true);
        await canonicalFile.writeAsBytes(preExistingBytes, flush: true);
        bridge.downloadResponse = {
          'ok': false,
          'errorCode': 'DOWNLOAD_FAILED',
          'errorMessage': 'Blob not found',
        };

        final result = await downloadMedia(
          owner: MediaOwnerLane.direct,
          bridge: bridge,
          mediaAttachmentRepo: mediaRepo,
          mediaFileManager: fileManager,
          attachment: testAttachment.copyWith(size: _jpegBytes.length),
          contactPeerId: 'contact-A',
        );

        expect(result, isNull);
        expect(bridge.sendCallCount, 1);
        expect(canonicalFile.existsSync(), isTrue);
        expect(canonicalFile.readAsBytesSync(), preExistingBytes);
        // INV-DL-4: a relay "not found" flips straight to the terminal
        // download_failed state (honest "expired on server"), not transient.
        expect(
          mediaRepo.downloadStatusUpdates,
          equals([
            (testAttachment.id, kMediaDownloadStatusDownloading),
            (testAttachment.id, kMediaDownloadStatusDownloadFailed),
          ]),
        );
        expect(mediaRepo.localPathUpdates, isEmpty);
      },
    );

    test(
      'downloadMedia validation failure after bridge success does not delete a pre-existing canonical file',
      () async {
        final preExistingBytes = <int>[8, 8];
        final canonicalPath = await fileManager.localPathForAttachment(
          contactPeerId: 'contact-A',
          blobId: testAttachment.id,
          mime: testAttachment.mime,
        );
        final canonicalFile = File(canonicalPath);
        await canonicalFile.parent.create(recursive: true);
        await canonicalFile.writeAsBytes(preExistingBytes, flush: true);
        bridge
          ..skipFileWrite = true
          ..downloadResponse = {
            'ok': true,
            'id': testAttachment.id,
            'mime': testAttachment.mime,
            'size': _jpegBytes.length,
          };

        final result = await downloadMedia(
          owner: MediaOwnerLane.direct,
          bridge: bridge,
          mediaAttachmentRepo: mediaRepo,
          mediaFileManager: fileManager,
          attachment: testAttachment.copyWith(size: _jpegBytes.length),
          contactPeerId: 'contact-A',
        );

        expect(result, isNull);
        expect(bridge.sendCallCount, 1);
        expect(canonicalFile.existsSync(), isTrue);
        expect(canonicalFile.readAsBytesSync(), preExistingBytes);
        expect(
          mediaRepo.downloadStatusUpdates,
          equals([
            (testAttachment.id, kMediaDownloadStatusDownloading),
            (testAttachment.id, kMediaDownloadStatusFailed),
          ]),
        );
        expect(mediaRepo.localPathUpdates, isEmpty);
      },
    );

    test('downloadMedia promotes staged file only after validation', () async {
      bridge
        ..downloadedBytes = _jpegBytes
        ..downloadResponse = {
          'ok': true,
          'id': testAttachment.id,
          'mime': testAttachment.mime,
          'size': _jpegBytes.length,
        };

      final result = await downloadMedia(
        owner: MediaOwnerLane.direct,
        bridge: bridge,
        mediaAttachmentRepo: mediaRepo,
        mediaFileManager: fileManager,
        attachment: testAttachment.copyWith(size: _jpegBytes.length),
        contactPeerId: 'contact-A',
      );

      final payload = bridge.lastRequest!['payload'] as Map<String, dynamic>;
      final downloadPath = payload['outputPath'] as String;
      final canonicalPath = await fileManager.localPathForAttachment(
        contactPeerId: 'contact-A',
        blobId: testAttachment.id,
        mime: testAttachment.mime,
      );

      expect(result, isNotNull);
      expect(result!.localPath, canonicalPath);
      expect(downloadPath, isNot(canonicalPath));
      expect(downloadPath, endsWith('.part'));
      expect(File(downloadPath).existsSync(), isFalse);
      expect(File(canonicalPath).existsSync(), isTrue);
      expect(File(canonicalPath).readAsBytesSync(), _jpegBytes);
      expect(
        mediaRepo.localPathUpdates,
        equals([
          (testAttachment.id, 'media/contact-A/${testAttachment.id}.jpg'),
        ]),
      );
    });

    test(
      'does not let failed fallback clobber local media that links during download',
      () async {
        final localPath =
            '${tempDir.path}/local_media/contact-A/blob-download-001.jpg';
        mediaRepo.seedAttachment(testAttachment);
        bridge.downloadResponse = {
          'ok': false,
          'errorCode': 'DOWNLOAD_FAILED',
          'errorMessage': 'Blob not found',
        };
        bridge.beforeDownloadResponse = (_) async {
          final file = File(localPath);
          await file.parent.create(recursive: true);
          await file.writeAsBytes(_jpegBytes, flush: true);
          await mediaRepo.updateLocalPath(testAttachment.id, localPath);
        };

        final result = await downloadMedia(
          owner: MediaOwnerLane.direct,
          bridge: bridge,
          mediaAttachmentRepo: mediaRepo,
          mediaFileManager: fileManager,
          attachment: testAttachment,
          contactPeerId: 'contact-A',
        );

        expect(result, isNotNull);
        expect(result!.downloadStatus, kMediaDownloadStatusDone);
        expect(result.localPath, localPath);
        expect(
          mediaRepo.downloadStatusUpdates,
          equals([('blob-download-001', kMediaDownloadStatusDownloading)]),
        );
        expect(
          mediaRepo.localPathUpdates,
          equals([('blob-download-001', localPath)]),
        );
      },
    );

    test(
      'repairs a failed attachment when the local media file already exists',
      () async {
        final localPath =
            '${tempDir.path}/local_media/contact-A/blob-download-001.jpg';
        final file = File(localPath);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(_jpegBytes, flush: true);
        final failedWithLocalFile = testAttachment.copyWith(
          localPath: localPath,
          downloadStatus: kMediaDownloadStatusFailed,
        );
        mediaRepo.seedAttachment(failedWithLocalFile);
        bridge.downloadResponse = {
          'ok': false,
          'errorCode': 'DOWNLOAD_FAILED',
          'errorMessage': 'Blob not found',
        };

        final result = await downloadMedia(
          owner: MediaOwnerLane.direct,
          bridge: bridge,
          mediaAttachmentRepo: mediaRepo,
          mediaFileManager: fileManager,
          attachment: failedWithLocalFile,
          contactPeerId: 'contact-A',
        );

        expect(result, isNotNull);
        expect(result!.downloadStatus, kMediaDownloadStatusDone);
        expect(result.localPath, localPath);
        expect(bridge.sendCallCount, 0);
        expect(
          mediaRepo.downloadStatusUpdates,
          equals([('blob-download-001', kMediaDownloadStatusDone)]),
        );
      },
    );

    test(
      'PL-013 keeps the staged partial on failed download and retry succeeds',
      () async {
        // Contract update (P0-C): the Dart side no longer destroys staged bytes
        // on a transient bridge failure — the Go side already removes genuine
        // partials it produced (pinned by TestPL013... in node/media_test.go),
        // and an incomplete leftover is ignored by adoption and overwritten by
        // the retry.
        final retryBridge = _FailOncePartialDownloadBridge()
          ..downloadedBytes = const <int>[1, 2, 3];

        final firstResult = await downloadMedia(
          owner: MediaOwnerLane.direct,
          bridge: retryBridge,
          mediaAttachmentRepo: mediaRepo,
          mediaFileManager: fileManager,
          attachment: testAttachment,
          contactPeerId: 'group-pl013',
        );

        expect(firstResult, isNull);
        expect(retryBridge.firstOutputPath, isNotNull);
        expect(
          File(retryBridge.firstOutputPath!).existsSync(),
          isTrue,
          reason: 'transient failure preserves the staged artifact',
        );
        expect(
          mediaRepo.downloadStatusUpdates,
          equals([
            ('blob-download-001', 'downloading'),
            ('blob-download-001', 'failed'),
          ]),
        );
        expect(mediaRepo.localPathUpdates, isEmpty);

        final retryResult = await downloadMedia(
          owner: MediaOwnerLane.direct,
          bridge: retryBridge,
          mediaAttachmentRepo: mediaRepo,
          mediaFileManager: fileManager,
          attachment: testAttachment,
          contactPeerId: 'group-pl013',
        );

        expect(retryResult, isNotNull);
        expect(retryResult!.downloadStatus, 'done');
        expect(File(retryResult.localPath!).existsSync(), isTrue);
        expect(
          mediaRepo.downloadStatusUpdates,
          equals([
            ('blob-download-001', 'downloading'),
            ('blob-download-001', 'failed'),
            ('blob-download-001', 'downloading'),
          ]),
        );
        expect(mediaRepo.localPathUpdates, hasLength(1));
      },
    );

    test('watchdog timeout preserves the .part file', () async {
      final timeoutBridge = _TimeoutAfterWriteBridge();
      final sizedAttachment = testAttachment.copyWith(size: 3);

      final result = await downloadMedia(
        owner: MediaOwnerLane.direct,
        bridge: timeoutBridge,
        mediaAttachmentRepo: mediaRepo,
        mediaFileManager: fileManager,
        attachment: sizedAttachment,
        contactPeerId: 'contact-A',
      );

      expect(result, isNull);
      expect(
        mediaRepo.downloadStatusUpdates.last.$2,
        'failed',
        reason: 'row goes failed so the UI can offer retry',
      );
      final partPath = '${tempDir.path}/contact-A/blob-download-001.jpg.part';
      expect(
        await File(partPath).exists(),
        isTrue,
        reason: 'transient failure must never destroy completed bytes',
      );
    });

    test('retry adopts complete .part without bridge call', () async {
      final sizedAttachment = testAttachment.copyWith(size: 3);
      final partPath = '${tempDir.path}/contact-A/blob-download-001.jpg.part';
      final partFile = File(partPath);
      await partFile.parent.create(recursive: true);
      await partFile.writeAsBytes(const [1, 2, 3], flush: true);

      final result = await downloadMedia(
        owner: MediaOwnerLane.direct,
        bridge: bridge,
        mediaAttachmentRepo: mediaRepo,
        mediaFileManager: fileManager,
        attachment: sizedAttachment,
        contactPeerId: 'contact-A',
      );

      expect(result, isNotNull);
      expect(result!.downloadStatus, 'done');
      expect(
        bridge.sendCallCount,
        0,
        reason: 'a complete .part is promoted without re-downloading',
      );
      expect(mediaRepo.localPathUpdates, hasLength(1));
      expect(
        await File('${tempDir.path}/contact-A/blob-download-001.jpg').exists(),
        isTrue,
      );
      expect(await partFile.exists(), isFalse, reason: 'renamed, not copied');

      // The relay ack still fires for the adopted bytes.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(bridge.deleteRequests, hasLength(1));
    });

    test('retry ignores incomplete .part and re-downloads', () async {
      final sizedAttachment = testAttachment.copyWith(size: 3);
      final partPath = '${tempDir.path}/contact-A/blob-download-001.jpg.part';
      final partFile = File(partPath);
      await partFile.parent.create(recursive: true);
      await partFile.writeAsBytes(const [9, 9], flush: true);

      final result = await downloadMedia(
        owner: MediaOwnerLane.direct,
        bridge: bridge,
        mediaAttachmentRepo: mediaRepo,
        mediaFileManager: fileManager,
        attachment: sizedAttachment,
        contactPeerId: 'contact-A',
      );

      expect(result, isNotNull);
      expect(result!.downloadStatus, 'done');
      expect(
        bridge.sendCallCount,
        1,
        reason: 'genuine partial goes through the normal download path',
      );
    });

    test('returns null and sets failed when bridge throws', () async {
      final throwBridge = _ThrowingBridge();

      final result = await downloadMedia(
        owner: MediaOwnerLane.direct,
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
        owner: MediaOwnerLane.direct,
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
          owner: MediaOwnerLane.direct,
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
      'group policy lets a local done file supersede an invalid in-flight download',
      () async {
        final groupAttachment = _encryptedGroupAttachment(
          testAttachment,
          _jpegBytes,
        ).copyWith(downloadStatus: kMediaDownloadStatusPending);
        mediaRepo.seedAttachment(groupAttachment);
        final relativePath = fileManager.relativePathForAttachment(
          contactPeerId: 'group-1',
          blobId: testAttachment.id,
          mime: testAttachment.mime,
        );
        final absolutePath = await fileManager.resolveStoredPath(relativePath);
        bridge
          ..skipFileWrite = true
          ..downloadResponse = {
            'ok': true,
            'id': testAttachment.id,
            'mime': testAttachment.mime,
            'size': _encryptedBytes(_jpegBytes).length,
          }
          ..beforeDownloadResponse = (_) async {
            final file = File(absolutePath);
            await file.parent.create(recursive: true);
            await file.writeAsBytes(_jpegBytes, flush: true);
            await mediaRepo.updateLocalPath(testAttachment.id, relativePath);
          };

        final events = await captureFlowEvents(() async {
          final result = await downloadMedia(
            owner: MediaOwnerLane.direct,
            bridge: bridge,
            mediaAttachmentRepo: mediaRepo,
            mediaFileManager: fileManager,
            attachment: groupAttachment,
            contactPeerId: 'group-1',
            enforceGroupMediaPolicy: true,
          );

          expect(result, isNotNull);
          expect(result!.downloadStatus, kMediaDownloadStatusDone);
          expect(result.localPath, absolutePath);
        });

        expect(
          mediaRepo.downloadStatusUpdates,
          isNot(
            contains((testAttachment.id, kMediaDownloadStatusIntegrityFailed)),
          ),
        );
        expect(
          events,
          contains(
            allOf(
              containsPair(
                'event',
                'MEDIA_DOWNLOAD_INVALID_GROUP_FILE_SUPERSEDED_BY_LOCAL',
              ),
            ),
          ),
        );
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
          owner: MediaOwnerLane.direct,
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
          owner: MediaOwnerLane.direct,
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
          owner: MediaOwnerLane.direct,
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
        owner: MediaOwnerLane.direct,
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

    test(
      'group policy emits delayed post-commit file existence probe',
      () async {
        debugGroupMediaDownloadPostCommitProbeDelays = const [Duration.zero];
        final events = <Map<String, dynamic>>[];
        debugSetFlowEventSink(events.add);
        addTearDown(() => debugSetFlowEventSink(null));
        final encrypted = _encryptedBytes(_jpegBytes);
        bridge.downloadedBytes = encrypted;
        bridge.downloadResponse = {
          'ok': true,
          'id': 'blob-download-001',
          'mime': 'image/jpeg',
          'size': encrypted.length,
        };

        final result = await downloadMedia(
          owner: MediaOwnerLane.direct,
          bridge: bridge,
          mediaAttachmentRepo: mediaRepo,
          mediaFileManager: fileManager,
          attachment: _encryptedGroupAttachment(testAttachment, _jpegBytes),
          contactPeerId: 'group-1',
          enforceGroupMediaPolicy: true,
        );
        expect(result, isNotNull);
        await _waitForCapturedFlowEvent(
          events,
          'MEDIA_GROUP_DURABLE_LOCAL_PATH_DELAYED_PROBE',
        );

        final probe = events.singleWhere(
          (event) =>
              event['event'] == 'MEDIA_GROUP_DURABLE_LOCAL_PATH_DELAYED_PROBE',
        );
        expect(
          probe['details'],
          allOf(
            containsPair('attachmentId', 'blob-download-001'),
            containsPair('source', 'group_media_download'),
            containsPair('relativePath', 'media/group-1/blob-download-001.jpg'),
            containsPair('fileExists', true),
            containsPair('fileBytes', _jpegBytes.length),
            containsPair('expectedBytes', _jpegBytes.length),
          ),
        );
        expect(
          events.map((event) => event['event']),
          isNot(
            contains('MEDIA_GROUP_DURABLE_LOCAL_PATH_DELAYED_PROBE_MISSING'),
          ),
        );
      },
    );

    test(
      'group policy restores migrated encrypted companion before relay download',
      () async {
        final encrypted = _encryptedBytes(_jpegBytes);
        final absolutePath = await fileManager.localPathForAttachment(
          contactPeerId: 'group-1',
          blobId: testAttachment.id,
          mime: testAttachment.mime,
        );
        final encryptedCompanion = File('$absolutePath.enc');
        await encryptedCompanion.parent.create(recursive: true);
        await encryptedCompanion.writeAsBytes(encrypted, flush: true);

        final result = await downloadMedia(
          owner: MediaOwnerLane.direct,
          bridge: bridge,
          mediaAttachmentRepo: mediaRepo,
          mediaFileManager: fileManager,
          attachment: _encryptedGroupAttachment(testAttachment, _jpegBytes),
          contactPeerId: 'group-1',
          enforceGroupMediaPolicy: true,
        );

        expect(result, isNotNull);
        expect(result!.downloadStatus, kMediaDownloadStatusDone);
        expect(result.localPath, absolutePath);
        expect(File(absolutePath).readAsBytesSync(), _jpegBytes);
        expect(encryptedCompanion.existsSync(), isFalse);
        expect(bridge.sendCallCount, 1);
        expect(bridge.lastRequest!['cmd'], 'blob:decrypt');
        expect(mediaRepo.downloadStatusUpdates, isEmpty);
        expect(
          mediaRepo.localPathUpdates,
          equals([
            (testAttachment.id, 'media/group-1/${testAttachment.id}.jpg'),
          ]),
        );
      },
    );

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
        owner: MediaOwnerLane.direct,
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
          owner: MediaOwnerLane.direct,
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
          owner: MediaOwnerLane.direct,
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
          owner: MediaOwnerLane.direct,
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
        owner: MediaOwnerLane.direct,
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
          owner: MediaOwnerLane.direct,
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
            owner: MediaOwnerLane.direct,
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
      'emits MEDIA_DOWNLOAD_LOCAL_MISS before fallback when migrated local file is missing',
      () async {
        final migratedAttachment = testAttachment.copyWith(
          localPath: 'media/contact-A/blob-download-001.jpg',
          downloadStatus: kMediaDownloadStatusDone,
        );
        mediaRepo.seedAttachment(migratedAttachment);
        bridge.downloadResponse = {
          'ok': true,
          'id': 'blob-download-001',
          'sourceRole': 'relay_media_store',
          'sourcePeerShort': 'relay-01',
          'streamTransport': 'direct',
          'servedByPhone': false,
          'routedViaRelayStore': true,
        };

        final events = await captureFlowEvents(() async {
          await downloadMedia(
            owner: MediaOwnerLane.direct,
            bridge: bridge,
            mediaAttachmentRepo: mediaRepo,
            mediaFileManager: fileManager,
            attachment: migratedAttachment,
            contactPeerId: 'contact-A',
          );
        });

        final miss = events.singleWhere(
          (event) => event['event'] == 'MEDIA_DOWNLOAD_LOCAL_MISS',
        );
        final details = miss['details'] as Map<String, dynamic>;
        expect(details['attachmentId'], 'blob-download-001');
        expect(details['messageId'], 'msg-001');
        expect(details['contactPeerShort'], 'contact-A');
        expect(details['mime'], 'image/jpeg');
        expect(details['reason'], 'local_file_missing');
        expect(details['candidateCount'], greaterThanOrEqualTo(1));
        final diagnostics = details['candidateDiagnostics'] as List<dynamic>;
        expect(
          diagnostics,
          contains(
            allOf(
              isA<Map<String, Object?>>(),
              containsPair('attachmentId', 'blob-download-001'),
              containsPair('localPathKind', 'relative'),
              containsPair('reason', 'local_file_missing'),
              containsPair('resolvedFileExists', false),
            ),
          ),
        );
        expect(bridge.lastRequest!['cmd'], 'media:download');
        final transportAudit = events.singleWhere(
          (event) => event['event'] == 'MEDIA_DOWNLOAD_TRANSPORT_AUDIT',
        );
        expect(
          transportAudit['details'],
          allOf(
            containsPair('attachmentId', 'blob-download-001'),
            containsPair('sourceRole', 'relay_media_store'),
            containsPair('servedByPhone', false),
            containsPair('routedViaRelayStore', true),
            containsPair('localMissReason', 'local_file_missing'),
          ),
        );
        final relayRisk = events.singleWhere(
          (event) => event['event'] == 'MEDIA_DOWNLOAD_RELAY_DEPENDENCY_RISK',
        );
        expect(
          relayRisk['details'],
          allOf(
            containsPair('attachmentId', 'blob-download-001'),
            containsPair('reason', 'local_file_missing'),
            containsPair('sourceRole', 'relay_media_store'),
            containsPair('routedViaRelayStore', true),
          ),
        );
        final staleClear = events.singleWhere(
          (event) =>
              event['event'] == 'MEDIA_DOWNLOAD_STALE_DONE_LOCAL_PATH_CLEARED',
        );
        expect(
          staleClear['details'],
          allOf(
            containsPair('attachmentId', 'blob-download-001'),
            containsPair('reason', 'local_file_missing'),
          ),
        );
        final durableCommit = events.singleWhere(
          (event) =>
              event['event'] == 'MEDIA_DOWNLOAD_DURABLE_LOCAL_PATH_COMMITTED',
        );
        expect(
          durableCommit['details'],
          allOf(
            containsPair('attachmentId', 'blob-download-001'),
            containsPair('source', 'direct_media_download'),
            containsPair('fileExists', true),
            containsPair('fileBytes', greaterThan(0)),
          ),
        );
      },
    );

    test(
      'overlapping callers for the same attachment trigger only one real download',
      () async {
        final delayedBridge = _DelayedBridge();

        final firstFuture = downloadMedia(
          owner: MediaOwnerLane.direct,
          bridge: delayedBridge,
          mediaAttachmentRepo: mediaRepo,
          mediaFileManager: fileManager,
          attachment: testAttachment,
          contactPeerId: 'contact-A',
        );
        await Future<void>.delayed(Duration.zero);

        final secondFuture = downloadMedia(
          owner: MediaOwnerLane.direct,
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
            // Generic transient error keeps the bounded `failed` state (the
            // concurrency behaviour under test); "not found" would be terminal.
            'errorMessage': 'relay temporarily unavailable',
          };

        final firstFuture = downloadMedia(
          owner: MediaOwnerLane.direct,
          bridge: delayedBridge,
          mediaAttachmentRepo: mediaRepo,
          mediaFileManager: fileManager,
          attachment: testAttachment,
          contactPeerId: 'contact-A',
        );
        await Future<void>.delayed(Duration.zero);

        final secondFuture = downloadMedia(
          owner: MediaOwnerLane.direct,
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

    test(
      'group download failure cleanup preserves an already committed plaintext file',
      () async {
        final encrypted = _encryptedBytes(_jpegBytes);
        bridge.downloadedBytes = encrypted;
        bridge.downloadResponse = {
          'ok': true,
          'id': testAttachment.id,
          'mime': testAttachment.mime,
          'size': encrypted.length,
        };
        final groupAttachment = _encryptedGroupAttachment(
          testAttachment,
          _jpegBytes,
        );

        final successful = await downloadMedia(
          owner: MediaOwnerLane.direct,
          bridge: bridge,
          mediaAttachmentRepo: mediaRepo,
          mediaFileManager: fileManager,
          attachment: groupAttachment,
          contactPeerId: 'group-1',
          enforceGroupMediaPolicy: true,
        );

        expect(successful, isNotNull);
        final committedPath = successful!.localPath!;
        expect(File(committedPath).existsSync(), isTrue);

        final staleRepo = _FakeMediaAttachmentRepo()
          ..seedAttachment(groupAttachment);
        final failed = await downloadMedia(
          owner: MediaOwnerLane.direct,
          bridge: _ThrowingBridge(),
          mediaAttachmentRepo: staleRepo,
          mediaFileManager: fileManager,
          attachment: groupAttachment,
          contactPeerId: 'group-1',
          enforceGroupMediaPolicy: true,
        );

        expect(failed, isNull);
        expect(File(committedPath).existsSync(), isTrue);
        expect(File(committedPath).readAsBytesSync(), _jpegBytes);
      },
    );

    // --- 112 Phase 1: direct (1:1) encrypted downloads ---
    // Receiver capability: per-attachment metadata-keyed decrypt, never
    // keyed on enforceGroupMediaPolicy. KC-3: ack-delete only after
    // decrypt + durable commit.
    group('direct encrypted downloads', () {
      Future<void> waitForAckDelete(_FakeBridge bridge) async {
        for (var attempt = 0; attempt < 100; attempt += 1) {
          if (bridge.deleteRequests.isNotEmpty) {
            return;
          }
          await Future<void>.delayed(const Duration(milliseconds: 2));
        }
      }

      test(
        'direct download decrypts encrypted attachment and commits plaintext',
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
            owner: MediaOwnerLane.direct,
            bridge: bridge,
            mediaAttachmentRepo: mediaRepo,
            mediaFileManager: fileManager,
            attachment: _encryptedGroupAttachment(testAttachment, _jpegBytes),
            contactPeerId: 'contact-A',
          );

          expect(result, isNotNull);
          expect(result!.downloadStatus, kMediaDownloadStatusDone);
          expect(result.localPath, isNotNull);
          expect(File(result.localPath!).readAsBytesSync(), _jpegBytes);
          expect(bridge.commandLog, contains('blob:decrypt'));
        },
      );

      test(
        'direct encrypted download stages to .enc, never promotes ciphertext '
        'to canonical',
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
            'ok': false,
            'errorMessage': 'decrypt failed',
          };

          final result = await downloadMedia(
            owner: MediaOwnerLane.direct,
            bridge: bridge,
            mediaAttachmentRepo: mediaRepo,
            mediaFileManager: fileManager,
            attachment: _encryptedGroupAttachment(testAttachment, _jpegBytes),
            contactPeerId: 'contact-A',
          );

          expect(result, isNull);
          final absolutePath = await fileManager.localPathForAttachment(
            contactPeerId: 'contact-A',
            blobId: 'blob-download-001',
            mime: 'image/jpeg',
          );
          expect(File(absolutePath).existsSync(), isFalse);
          expect(File('$absolutePath.part').existsSync(), isFalse);
          // Staged ciphertext preserved for retry — relay copy stays alive.
          expect(File('$absolutePath.enc').existsSync(), isTrue);
          expect(mediaRepo.downloadStatusUpdates.last, (
            'blob-download-001',
            kMediaDownloadStatusIntegrityFailed,
          ));
          expect(mediaRepo.localPathUpdates, isEmpty);
          expect(bridge.deleteRequests, isEmpty);
        },
      );

      test('ack delete fires only after decrypt and durable commit', () async {
        final encrypted = _encryptedBytes(_jpegBytes);
        bridge.downloadedBytes = encrypted;
        bridge.downloadResponse = {
          'ok': true,
          'id': 'blob-download-001',
          'mime': 'image/jpeg',
          'size': encrypted.length,
        };
        var localPathUpdatesAtDeleteTime = -1;
        bridge.onDeleteRequest = () {
          localPathUpdatesAtDeleteTime = mediaRepo.localPathUpdates.length;
        };

        final result = await downloadMedia(
          owner: MediaOwnerLane.direct,
          bridge: bridge,
          mediaAttachmentRepo: mediaRepo,
          mediaFileManager: fileManager,
          attachment: _encryptedGroupAttachment(testAttachment, _jpegBytes),
          contactPeerId: 'contact-A',
        );

        expect(result, isNotNull);
        await waitForAckDelete(bridge);
        expect(bridge.deleteRequests, hasLength(1));
        // KC-3: the relay copy is released only after the durable commit.
        expect(localPathUpdatesAtDeleteTime, 1);
        expect(
          bridge.commandLog.indexOf('blob:decrypt'),
          lessThan(bridge.commandLog.indexOf('media:delete')),
        );
      });

      test('cross-object key reuse fails closed for direct media', () async {
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
          owner: MediaOwnerLane.direct,
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
          contactPeerId: 'contact-A',
        );

        expect(result, isNull);
        expect(mediaRepo.downloadStatusUpdates.last, (
          'blob-download-001',
          kMediaDownloadStatusIntegrityFailed,
        ));
        expect(mediaRepo.localPathUpdates, isEmpty);
        final absolutePath = await fileManager.localPathForAttachment(
          contactPeerId: 'contact-A',
          blobId: 'blob-download-001',
          mime: 'image/jpeg',
        );
        expect(File(absolutePath).existsSync(), isFalse);
        expect(bridge.deleteRequests, isEmpty);
      });

      test(
        'unknown encryptionScheme fails closed without ack delete',
        () async {
          // Discriminator case 3: key material present, scheme outside the
          // v1 whitelist. Must never be decrypted with v1 logic, never
          // promoted, never acked — a future scheme's relay copy is the only
          // recoverable artifact.
          final encrypted = _encryptedBytes(_jpegBytes);
          bridge.downloadedBytes = encrypted;
          bridge.downloadResponse = {
            'ok': true,
            'id': 'blob-download-001',
            'mime': 'image/jpeg',
            'size': encrypted.length,
          };

          final result = await downloadMedia(
            owner: MediaOwnerLane.direct,
            bridge: bridge,
            mediaAttachmentRepo: mediaRepo,
            mediaFileManager: fileManager,
            attachment: _encryptedGroupAttachment(
              testAttachment,
              _jpegBytes,
            ).copyWith(encryptionScheme: 'blob_aes_256_gcm_v2_future'),
            contactPeerId: 'contact-A',
          );

          expect(result, isNull);
          expect(bridge.commandLog, isNot(contains('blob:decrypt')));
          final absolutePath = await fileManager.localPathForAttachment(
            contactPeerId: 'contact-A',
            blobId: 'blob-download-001',
            mime: 'image/jpeg',
          );
          expect(File(absolutePath).existsSync(), isFalse);
          expect(File('$absolutePath.enc').existsSync(), isTrue);
          expect(mediaRepo.downloadStatusUpdates.last, (
            'blob-download-001',
            kMediaDownloadStatusIntegrityFailed,
          ));
          expect(bridge.deleteRequests, isEmpty);
        },
      );

      test(
        'content hash mismatch on encrypted direct blob fails before decrypt',
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
            owner: MediaOwnerLane.direct,
            bridge: bridge,
            mediaAttachmentRepo: mediaRepo,
            mediaFileManager: fileManager,
            attachment: _encryptedGroupAttachment(
              testAttachment,
              _jpegBytes,
              contentHash: _hashBytes('spoofed-bytes'.codeUnits),
            ),
            contactPeerId: 'contact-A',
          );

          expect(result, isNull);
          expect(bridge.commandLog, isNot(contains('blob:decrypt')));
          expect(mediaRepo.downloadStatusUpdates.last, (
            'blob-download-001',
            kMediaDownloadStatusIntegrityFailed,
          ));
          expect(mediaRepo.localPathUpdates, isEmpty);
          final absolutePath = await fileManager.localPathForAttachment(
            contactPeerId: 'contact-A',
            blobId: 'blob-download-001',
            mime: 'image/jpeg',
          );
          expect(File(absolutePath).existsSync(), isFalse);
          expect(bridge.deleteRequests, isEmpty);
        },
      );

      test('transient bridge failure during decrypt keeps .enc and stays '
          'retryable', () async {
        final encrypted = _encryptedBytes(_jpegBytes);
        bridge.downloadedBytes = encrypted;
        bridge.downloadResponse = {
          'ok': true,
          'id': 'blob-download-001',
          'mime': 'image/jpeg',
          'size': encrypted.length,
        };
        bridge.throwOnDecrypt = true;

        final result = await downloadMedia(
          owner: MediaOwnerLane.direct,
          bridge: bridge,
          mediaAttachmentRepo: mediaRepo,
          mediaFileManager: fileManager,
          attachment: _encryptedGroupAttachment(testAttachment, _jpegBytes),
          contactPeerId: 'contact-A',
        );

        expect(result, isNull);
        // Retryable failed — NOT integrity_failed: the ciphertext was
        // never cryptographically evaluated.
        expect(mediaRepo.downloadStatusUpdates.last, (
          'blob-download-001',
          kMediaDownloadStatusFailed,
        ));
        final absolutePath = await fileManager.localPathForAttachment(
          contactPeerId: 'contact-A',
          blobId: 'blob-download-001',
          mime: 'image/jpeg',
        );
        expect(File('$absolutePath.enc').existsSync(), isTrue);
        expect(bridge.deleteRequests, isEmpty);
      });

      test('legacy plaintext direct attachment stays decrypt-free', () async {
        // Green pin guarding the mixed-version grace window: no key
        // material → today's `.part` staging + promote + ack, no decrypt.
        final result = await downloadMedia(
          owner: MediaOwnerLane.direct,
          bridge: bridge,
          mediaAttachmentRepo: mediaRepo,
          mediaFileManager: fileManager,
          attachment: testAttachment,
          contactPeerId: 'contact-A',
        );

        expect(result, isNotNull);
        expect(result!.downloadStatus, kMediaDownloadStatusDone);
        expect(bridge.commandLog, isNot(contains('blob:decrypt')));
        final payload = bridge.lastRequest!['payload'] as Map<String, dynamic>;
        expect(payload['outputPath'], endsWith('.part'));
        await waitForAckDelete(bridge);
        expect(bridge.deleteRequests, hasLength(1));
      });

      test('retry adopts complete encrypted staged artifact via '
          'decrypt-then-promote', () async {
        // 'cipher:kkkk:nnn:' prefix is exactly 16 bytes, so the fake
        // ciphertext is plaintext + 16 — matching the real AES-GCM tag
        // overhead the adoption gate expects.
        const key = 'kkkk';
        const nonce = 'nnn';
        final encrypted = _encryptedBytes(_jpegBytes, key: key, nonce: nonce);
        expect(encrypted.length, _jpegBytes.length + 16);

        final attachment = _encryptedGroupAttachment(
          testAttachment,
          _jpegBytes,
          key: key,
          nonce: nonce,
          contentHash: _hashBytes(encrypted),
        );
        final absolutePath = await fileManager.localPathForAttachment(
          contactPeerId: 'contact-A',
          blobId: attachment.id,
          mime: attachment.mime,
        );
        final staged = File('$absolutePath.enc');
        await staged.parent.create(recursive: true);
        await staged.writeAsBytes(encrypted, flush: true);

        var localPathUpdatesAtDeleteTime = -1;
        bridge.onDeleteRequest = () {
          localPathUpdatesAtDeleteTime = mediaRepo.localPathUpdates.length;
        };

        final result = await downloadMedia(
          owner: MediaOwnerLane.direct,
          bridge: bridge,
          mediaAttachmentRepo: mediaRepo,
          mediaFileManager: fileManager,
          attachment: attachment,
          contactPeerId: 'contact-A',
        );

        expect(result, isNotNull);
        expect(result!.downloadStatus, kMediaDownloadStatusDone);
        expect(File(absolutePath).readAsBytesSync(), _jpegBytes);
        expect(bridge.commandLog, isNot(contains('media:download')));
        expect(
          bridge.commandLog.where((cmd) => cmd == 'blob:decrypt'),
          hasLength(1),
        );
        await waitForAckDelete(bridge);
        expect(bridge.deleteRequests, hasLength(1));
        expect(localPathUpdatesAtDeleteTime, 1);
      });

      test(
        'adoption ignores encrypted artifact with wrong staged size',
        () async {
          const key = 'kkkk';
          const nonce = 'nnn';
          final encrypted = _encryptedBytes(_jpegBytes, key: key, nonce: nonce);
          final attachment = _encryptedGroupAttachment(
            testAttachment,
            _jpegBytes,
            key: key,
            nonce: nonce,
            contentHash: _hashBytes(encrypted),
          );
          final absolutePath = await fileManager.localPathForAttachment(
            contactPeerId: 'contact-A',
            blobId: attachment.id,
            mime: attachment.mime,
          );
          final staged = File('$absolutePath.enc');
          await staged.parent.create(recursive: true);
          // Truncated artifact — a genuine partial; must NOT be adopted.
          await staged.writeAsBytes(
            encrypted.sublist(0, encrypted.length - 3),
            flush: true,
          );

          bridge.downloadedBytes = encrypted;
          bridge.downloadResponse = {
            'ok': true,
            'id': attachment.id,
            'mime': attachment.mime,
            'size': encrypted.length,
          };

          final result = await downloadMedia(
            owner: MediaOwnerLane.direct,
            bridge: bridge,
            mediaAttachmentRepo: mediaRepo,
            mediaFileManager: fileManager,
            attachment: attachment,
            contactPeerId: 'contact-A',
          );

          expect(result, isNotNull);
          expect(result!.downloadStatus, kMediaDownloadStatusDone);
          // PL-013 preserved: genuine partials re-download.
          expect(bridge.commandLog, contains('media:download'));
          expect(File(absolutePath).readAsBytesSync(), _jpegBytes);
        },
      );
    });
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
