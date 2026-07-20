import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/application/download_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';

import '../../../shared/fakes/in_memory_message_repository.dart';

/// Simulates the new transfer policy end-to-end in fast test time:
/// a slow-but-moving transfer (progress events keep arriving) survives a
/// short stall budget, while a genuinely stalled transfer fails with the
/// typed watchdog code and PRESERVES its staged artifact.
///
/// 09-P1 NOTE (G-09-2): the bounded-download-retry sim proofs (INV-DL-1 retry
/// counter increment + ceiling flip to terminal `download_failed`, INV-DL-2
/// counter reset on transient-then-success, INV-DL-4 relay not-found/not-authorized
/// 0-budget short-circuit, and convergence within kMaxDownloadRetries without
/// infinite retry) live in `download_media_use_case_test.dart` (the INV-DL-1/2/4
/// tests in the `downloadMedia` group), which drives the REAL downloadMedia +
/// saveAttachment persistence against a fake bridge. They were placed there
/// rather than re-deriving a `_NotFoundBridge` here, so this file's stall-only
/// scope is not a coverage gap for finding 09.
class _SlowWritingBridge extends Bridge {
  final Duration delay;
  final List<int> bytes = const [1, 2, 3];
  bool writeFile = true;

  _SlowWritingBridge({
    required this.delay,
  });

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
    if (request['cmd'] == 'media:delete') {
      return jsonEncode({'ok': true});
    }
    await Future<void>.delayed(delay);
    final payload = request['payload'] as Map<String, dynamic>?;
    final outputPath = payload?['outputPath'] as String?;
    if (writeFile && outputPath != null) {
      final file = File(outputPath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
    }
    return jsonEncode({'ok': true});
  }
}

class _HangingBridge extends Bridge {
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
  Future<String> send(String message) => Completer<String>().future;
}

class _RecorderRepo implements MediaAttachmentRepository {
  final List<(String, String)> downloadStatusUpdates = [];
  final List<(String, String)> localPathUpdates = [];

  @override
  Future<void> saveAttachment(
    MediaAttachment attachment, {
    required MediaOwnerLane owner,
  }) async {}
  @override
  Future<List<MediaAttachment>> getAttachmentsForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) async => const [];
  @override
  Future<Map<String, List<MediaAttachment>>> getAttachmentsForMessages(
    List<String> messageIds, {
    required MediaOwnerLane owner,
  }) async => const {};
  @override
  Future<void> updateLocalPath(String id, String localPath) async {
    localPathUpdates.add((id, localPath));
  }

  @override
  Future<void> updateDownloadStatus(String id, String downloadStatus) async {
    downloadStatusUpdates.add((id, downloadStatus));
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
  Future<List<MediaAttachment>> getPendingDownloads() async => const [];
  @override
  Future<List<MediaAttachment>> getUploadPendingAttachments({
    required MediaOwnerLane owner,
  }) async => const [];
}

class _TempMediaFileManager extends MediaFileManager {
  final String basePath;
  _TempMediaFileManager(this.basePath);

  @override
  Future<String> localPathForAttachment({
    required String contactPeerId,
    required String blobId,
    required String mime,
  }) async => '$basePath/$contactPeerId/$blobId.jpg';

  @override
  Future<String> resolveStoredPath(String storedPath) async =>
      storedPath.startsWith('/') ? storedPath : '$basePath/$storedPath';
}

void main() {
  late Directory tempDir;
  late _RecorderRepo repo;
  late _TempMediaFileManager fileManager;
  late InMemoryMessageRepository messageRepo;
  final flowEvents = <Map<String, dynamic>>[];

  const attachment = MediaAttachment(
    id: 'blob-slow-sim-001',
    messageId: 'msg-sim-001',
    mime: 'image/jpeg',
    size: 3,
    mediaType: 'image',
    downloadStatus: 'pending',
    createdAt: '2026-06-12T10:00:00.000Z',
  );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('slow_transfer_sim_');
    repo = _RecorderRepo();
    fileManager = _TempMediaFileManager(tempDir.path);
    messageRepo = InMemoryMessageRepository();
    const now = '2026-06-12T10:00:00.000Z';
    await messageRepo.saveMessage(
      const ConversationMessage(
        id: 'msg-sim-001',
        contactPeerId: 'contact-sim',
        senderPeerId: 'contact-sim',
        text: '',
        timestamp: now,
        status: 'delivered',
        isIncoming: true,
        createdAt: now,
      ),
    );
    flowEvents.clear();
    debugSetFlowEventSink(
      (payload) => flowEvents.add(Map<String, dynamic>.from(payload)),
    );
  });

  tearDown(() async {
    debugSetFlowEventSink(null);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('slow steady transfer with progress completes; stalled transfer fails '
      'with typed stall code', () async {
    // --- slow but steady: progress events outlive the stall budget ---
    final slowBridge = _SlowWritingBridge(
      delay: const Duration(milliseconds: 400),
    );
    final ticker = Timer.periodic(const Duration(milliseconds: 40), (_) {
      emitMediaDownloadProgressEvent({
        'id': attachment.id,
        'receivedBytes': 1,
        'totalBytes': 3,
        'fromPeerId': 'relay-sim',
      });
    });

    MediaAttachment? slowResult;
    try {
      slowResult = await downloadMedia(
        owner: MediaOwnerLane.direct,
        bridge: slowBridge,
        mediaAttachmentRepo: repo,
        mediaFileManager: fileManager,
        attachment: attachment,
        contactPeerId: 'contact-sim',
        messageRepo: messageRepo,
        transferStallTimeout: const Duration(milliseconds: 150),
        transferMaxTimeout: const Duration(seconds: 10),
      );
    } finally {
      ticker.cancel();
    }

    expect(
      slowResult,
      isNotNull,
      reason: 'a moving transfer must never die on a fixed wall clock',
    );
    expect(slowResult!.downloadStatus, 'done');

    // --- genuinely stalled: typed watchdog code + preserved artifact ---
    final stalledResult = await downloadMedia(
      owner: MediaOwnerLane.direct,
      bridge: _HangingBridge(),
      mediaAttachmentRepo: repo,
      mediaFileManager: fileManager,
      attachment: attachment.copyWith(id: 'blob-stalled-001'),
      contactPeerId: 'contact-sim',
      messageRepo: messageRepo,
      transferStallTimeout: const Duration(milliseconds: 120),
      transferMaxTimeout: const Duration(seconds: 10),
    );

    expect(stalledResult, isNull);
    expect(repo.downloadStatusUpdates.last, ('blob-stalled-001', 'failed'));

    final watchdogEvent = flowEvents.firstWhere(
      (event) => event['event'] == 'MEDIA_TRANSFER_WATCHDOG_TIMEOUT',
    );
    final details = watchdogEvent['details'] as Map<String, dynamic>;
    expect(details['reason'], 'stalled_no_progress');
    expect(details['operation'], 'media:download');

    expect(
      flowEvents.any(
        (event) => event['event'] == 'MEDIA_DOWNLOAD_PART_PRESERVED',
      ),
      isTrue,
      reason: 'stall failures must preserve staged bytes, never delete',
    );
  });
}
