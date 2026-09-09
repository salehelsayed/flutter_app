import 'package:flutter_app/core/diagnostics/app_diagnostics.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_app/core/database/direct_media_blob_custody.dart'
    show
        DirectMediaBlobCustodyDirection,
        DirectMediaBlobCustodyRow,
        DirectMediaBlobCustodyState,
        MediaBlobCustodyOwnerLane,
        kGroupMediaBlobCustodyKind;
import 'package:flutter_app/core/database/helpers/direct_media_blob_custody_db_helpers.dart'
    show kDirectMediaBlobCustodyTable;
import 'package:flutter_app/core/media/direct_media_blob_custody.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/constants/retry_constants.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/group_media_blob_custody.dart';
import 'package:flutter_app/core/media/group_media_size_policy.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_attachment_lifecycle_lock.dart';
import 'package:flutter_app/core/media/direct_private_media_transfer_registry.dart';
import 'package:flutter_app/core/media/media_storage_manager.dart';
import 'package:flutter_app/core/media/private_media_lifecycle_engine.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/application/download_media_use_case.dart'
    hide downloadMedia;
import 'package:flutter_app/features/conversation/application/download_media_use_case.dart'
    as download_use_case
    show downloadMedia;
import 'package:flutter_app/features/conversation/application/strict_direct_media_blob_download_ack_owner.dart';
import 'package:flutter_app/features/conversation/application/direct_private_media_lifecycle.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/media_library.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/application/strict_group_media_blob_download_ack_owner.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart';

import '../../../shared/fixtures/media_repository_real_db_fixture.dart';
import '../../../shared/fakes/in_memory_message_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';

late MessageRepository _defaultDirectMessageRepo;

class _OrdinaryParentMessageRepository extends InMemoryMessageRepository {
  @override
  Future<ConversationMessage?> getMessage(String id) async {
    return await super.getMessage(id) ??
        ConversationMessage(
          id: id,
          contactPeerId: 'contact-A',
          senderPeerId: 'sender-A',
          text: '',
          timestamp: '2026-02-20T10:00:00.000Z',
          status: 'delivered',
          isIncoming: true,
          createdAt: '2026-02-20T10:00:00.000Z',
        );
  }
}

Future<MediaAttachment?> downloadMedia({
  required Bridge bridge,
  required MediaAttachmentRepository mediaAttachmentRepo,
  required MediaFileManager mediaFileManager,
  required MediaAttachment attachment,
  required String contactPeerId,
  required MediaOwnerLane owner,
  MessageRepository? messageRepo,
  GroupMessageRepository? groupMessageRepo,
  MediaDownloadIntent? intent,
  bool enforceGroupMediaPolicy = false,
  Duration? transferStallTimeout,
  Duration? transferMaxTimeout,
  Duration? latePrivateTransferScrubDelay,
  int Function()? nowMs,
  GroupMediaAutomaticDownloadAttemptStarted?
  groupMediaAutomaticDownloadAttemptStarted,
  GroupMediaPostClaimPreCommit? groupMediaPostClaimPreCommit,
}) {
  return download_use_case.downloadMedia(
    bridge: bridge,
    mediaAttachmentRepo: mediaAttachmentRepo,
    mediaFileManager: mediaFileManager,
    attachment: attachment,
    contactPeerId: contactPeerId,
    owner: owner,
    messageRepo:
        messageRepo ??
        (owner == MediaOwnerLane.direct ? _defaultDirectMessageRepo : null),
    groupMessageRepo: groupMessageRepo,
    intent: intent,
    enforceGroupMediaPolicy: enforceGroupMediaPolicy,
    transferStallTimeout: transferStallTimeout,
    transferMaxTimeout: transferMaxTimeout,
    latePrivateTransferScrubDelay: latePrivateTransferScrubDelay,
    nowMs: nowMs,
    groupMediaAutomaticDownloadAttemptStarted:
        groupMediaAutomaticDownloadAttemptStarted,
    groupMediaPostClaimPreCommit: groupMediaPostClaimPreCommit,
  );
}

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
  FutureOr<void> Function()? onDeleteRequest;

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    commandLog.add(parsed['cmd'] as String);
    if (parsed['cmd'] == 'media:delete') {
      deleteRequests.add(parsed);
      await onDeleteRequest?.call();
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
        return jsonEncode({
          'ok': false,
          'errorCode': 'DECRYPT_AUTH_ERROR',
          'errorMessage': 'decrypt failed',
        });
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
      await beforeDownloadResponse?.call(parsed);
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
class _FakeMediaAttachmentRepo
    implements
        MediaAttachmentRepository,
        DirectPrivateMediaDownloadStateRepository,
        DirectPrivateMediaCleanupRuntime {
  final List<(String, String)> downloadStatusUpdates = [];
  final List<(String, String)> localPathUpdates = [];
  final Map<String, List<MediaAttachment>> _attachmentsByMessage = {};
  final MediaAttachmentLifecycleLock _lifecycleLock =
      MediaAttachmentLifecycleLock();

  @override
  MediaAttachmentLifecycleLock get directPrivateMediaLifecycleLock =>
      _lifecycleLock;

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
    final stored = attachment.ownerLane == null
        ? attachment.copyWith(ownerLane: MediaOwnerLane.direct)
        : attachment;
    final attachments = _attachmentsByMessage.putIfAbsent(
      stored.messageId,
      () => <MediaAttachment>[],
    );
    attachments.removeWhere((candidate) => candidate.id == stored.id);
    attachments.add(stored);
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

  MediaAttachment? _findAttachment(String id) {
    for (final attachments in _attachmentsByMessage.values) {
      for (final attachment in attachments) {
        if (attachment.id == id) return attachment;
      }
    }
    return null;
  }

  @override
  Future<bool> beginDirectPrivateMediaDownload(
    String id, {
    required String messageId,
    required int nowMs,
  }) => _lifecycleLock.synchronized(
    id,
    () => beginDirectPrivateMediaDownloadWithinLock(
      id,
      messageId: messageId,
      nowMs: nowMs,
    ),
  );

  @override
  Future<bool> beginDirectPrivateMediaDownloadWithinLock(
    String id, {
    required String messageId,
    required int nowMs,
  }) async {
    final current = _findAttachment(id);
    if (current == null ||
        current.messageId != messageId ||
        current.downloadStatus == kMediaDownloadStatusDownloading) {
      return false;
    }
    _updateAttachment(
      id,
      (item) => item.copyWith(downloadStatus: kMediaDownloadStatusDownloading),
    );
    return true;
  }

  @override
  Future<bool> qualifyDirectPrivateMediaLocalReady(
    String id, {
    required String messageId,
    required String expectedLocalPath,
    required int nowMs,
  }) => _lifecycleLock.synchronized(
    id,
    () => qualifyDirectPrivateMediaLocalReadyWithinLock(
      id,
      messageId: messageId,
      expectedLocalPath: expectedLocalPath,
      nowMs: nowMs,
    ),
  );

  @override
  Future<bool> qualifyDirectPrivateMediaLocalReadyWithinLock(
    String id, {
    required String messageId,
    required String expectedLocalPath,
    required int nowMs,
  }) async {
    final current = _findAttachment(id);
    return current?.messageId == messageId &&
        current?.downloadStatus == kMediaDownloadStatusDone &&
        current?.localPath == expectedLocalPath;
  }

  @override
  Future<bool> qualifyDirectPrivateMediaDownloadClaimWithinLock(
    String id, {
    required String messageId,
    required int nowMs,
  }) async {
    final current = _findAttachment(id);
    return current?.messageId == messageId &&
        current?.downloadStatus == kMediaDownloadStatusDownloading;
  }

  @override
  Future<bool> recordDirectPrivateMediaDownloadFailure(
    String id, {
    required String messageId,
    required int nowMs,
    required bool incrementRetryCount,
    required String failureStatus,
    required String expectedDownloadStatus,
    String? expectedLocalPath,
    bool clearLocalPath = false,
  }) => _lifecycleLock.synchronized(
    id,
    () => recordDirectPrivateMediaDownloadFailureWithinLock(
      id,
      messageId: messageId,
      nowMs: nowMs,
      incrementRetryCount: incrementRetryCount,
      failureStatus: failureStatus,
      expectedDownloadStatus: expectedDownloadStatus,
      expectedLocalPath: expectedLocalPath,
      clearLocalPath: clearLocalPath,
    ),
  );

  @override
  Future<bool> recordDirectPrivateMediaDownloadFailureWithinLock(
    String id, {
    required String messageId,
    required int nowMs,
    required bool incrementRetryCount,
    required String failureStatus,
    required String expectedDownloadStatus,
    String? expectedLocalPath,
    bool clearLocalPath = false,
  }) async {
    final current = _findAttachment(id);
    if (current == null ||
        current.messageId != messageId ||
        current.downloadStatus != expectedDownloadStatus ||
        (expectedLocalPath != null && current.localPath != expectedLocalPath)) {
      return false;
    }
    final nextRetry = (current.downloadRetryCount ?? 0) + 1;
    _updateAttachment(
      id,
      (item) => item.copyWith(
        downloadStatus: incrementRetryCount && nextRetry >= kMaxDownloadRetries
            ? kMediaDownloadStatusDownloadFailed
            : failureStatus,
        downloadRetryCount: incrementRetryCount
            ? nextRetry
            : current.downloadRetryCount,
        clearLocalPath: clearLocalPath,
      ),
    );
    return true;
  }

  @override
  Future<bool> commitDirectPrivateMediaDownloadLocalPath(
    String id, {
    required String messageId,
    required String localPath,
    required int nowMs,
  }) => _lifecycleLock.synchronized(
    id,
    () => commitDirectPrivateMediaDownloadLocalPathWithinLock(
      id,
      messageId: messageId,
      localPath: localPath,
      nowMs: nowMs,
    ),
  );

  @override
  Future<bool> commitDirectPrivateMediaDownloadLocalPathWithinLock(
    String id, {
    required String messageId,
    required String localPath,
    required int nowMs,
  }) async {
    final current = _findAttachment(id);
    if (current == null ||
        current.messageId != messageId ||
        current.downloadStatus != kMediaDownloadStatusDownloading) {
      return false;
    }
    localPathUpdates.add((id, localPath));
    _updateAttachment(
      id,
      (item) => item.copyWith(
        localPath: localPath,
        downloadStatus: kMediaDownloadStatusDone,
        downloadRetryCount: 0,
      ),
    );
    return true;
  }
}

class _AtomicOrdinaryGroupFailureMediaRepo extends _FakeMediaAttachmentRepo
    implements
        MediaDownloadStateRepository,
        OrdinaryGroupAutomaticMediaDownloadStateRepository,
        OrdinaryGroupExplicitMediaDownloadStateRepository,
        OrdinaryGroupMediaDownloadFailureRepository {
  final List<
    ({
      String id,
      String groupId,
      String messageId,
      bool incrementRetryCount,
      String failureStatus,
      String expectedDownloadStatus,
      String? expectedLocalPath,
      bool clearLocalPath,
    })
  >
  atomicFailureCalls = [];
  int legacySaveCalls = 0;
  FutureOr<void> Function(String id)? beforeAutomaticBegin;
  FutureOr<void> Function(String id)? beforeAutomaticCommit;
  FutureOr<void> Function(String id)? beforeExplicitBegin;
  FutureOr<void> Function(String id)? beforeExplicitCommit;
  int automaticBeginCalls = 0;
  int automaticCommitCalls = 0;
  int explicitBeginCalls = 0;
  int explicitCommitCalls = 0;
  bool automaticParentPresent = true;
  bool automaticParentLocallyDeleted = false;
  String? automaticParentGroupId;
  bool automaticDeletionJournaled = false;

  @override
  Future<void> saveAttachment(
    MediaAttachment attachment, {
    required MediaOwnerLane owner,
  }) async {
    legacySaveCalls += 1;
    await super.saveAttachment(attachment, owner: owner);
  }

  @override
  Future<bool> beginMediaDownload(
    String id, {
    required MediaOwnerLane owner,
  }) async {
    final current = _findAttachment(id);
    if (current == null ||
        current.ownerLane != owner ||
        !const {
          kMediaDownloadStatusPending,
          kMediaDownloadStatusDownloading,
          kMediaDownloadStatusFailed,
          kMediaDownloadStatusDownloadFailed,
          kMediaDownloadStatusEvicted,
        }.contains(current.downloadStatus)) {
      return false;
    }
    _updateAttachment(
      id,
      (item) => item.copyWith(downloadStatus: kMediaDownloadStatusDownloading),
    );
    return true;
  }

  @override
  Future<bool> commitMediaDownloadLocalPath(
    String id, {
    required MediaOwnerLane owner,
    required String localPath,
  }) async {
    final current = _findAttachment(id);
    if (current == null ||
        current.ownerLane != owner ||
        current.downloadStatus != kMediaDownloadStatusDownloading) {
      return false;
    }
    _updateAttachment(
      id,
      (item) => item.copyWith(
        localPath: localPath,
        downloadStatus: kMediaDownloadStatusDone,
        downloadRetryCount: 0,
      ),
    );
    return true;
  }

  @override
  Future<bool> beginOrdinaryGroupAutomaticMediaDownload(
    String id, {
    required String groupId,
    required String messageId,
    required String expectedDownloadStatus,
    required String? expectedLocalPath,
  }) async {
    automaticBeginCalls += 1;
    await beforeAutomaticBegin?.call(id);
    final current = _findAttachment(id);
    if (current == null ||
        !automaticParentPresent ||
        automaticParentLocallyDeleted ||
        (automaticParentGroupId != null && automaticParentGroupId != groupId) ||
        automaticDeletionJournaled ||
        current.ownerLane != MediaOwnerLane.group ||
        current.messageId != messageId ||
        current.downloadStatus != expectedDownloadStatus ||
        current.localPath != expectedLocalPath ||
        (current.downloadRetryCount ?? 0) >= kMaxDownloadRetries ||
        !const {
          kMediaDownloadStatusPending,
          kMediaDownloadStatusDownloading,
          kMediaDownloadStatusFailed,
        }.contains(current.downloadStatus)) {
      return false;
    }
    _updateAttachment(
      id,
      (item) => item.copyWith(downloadStatus: kMediaDownloadStatusDownloading),
    );
    return true;
  }

  @override
  Future<bool> commitOrdinaryGroupAutomaticMediaDownloadLocalPath(
    String id, {
    required String groupId,
    required String messageId,
    required String? expectedLocalPath,
    required String localPath,
  }) async {
    automaticCommitCalls += 1;
    await beforeAutomaticCommit?.call(id);
    final current = _findAttachment(id);
    if (current == null ||
        !automaticParentPresent ||
        automaticParentLocallyDeleted ||
        (automaticParentGroupId != null && automaticParentGroupId != groupId) ||
        automaticDeletionJournaled ||
        current.ownerLane != MediaOwnerLane.group ||
        current.messageId != messageId ||
        current.downloadStatus != kMediaDownloadStatusDownloading ||
        current.localPath != expectedLocalPath) {
      return false;
    }
    _updateAttachment(
      id,
      (item) => item.copyWith(
        localPath: localPath,
        downloadStatus: kMediaDownloadStatusDone,
        downloadRetryCount: 0,
      ),
    );
    return true;
  }

  @override
  Future<bool> beginOrdinaryGroupExplicitMediaDownload(
    String id, {
    required String groupId,
    required String messageId,
    required String expectedDownloadStatus,
    required String? expectedLocalPath,
  }) async {
    explicitBeginCalls += 1;
    await beforeExplicitBegin?.call(id);
    final current = _findAttachment(id);
    if (current == null ||
        !automaticParentPresent ||
        automaticParentLocallyDeleted ||
        (automaticParentGroupId != null && automaticParentGroupId != groupId) ||
        automaticDeletionJournaled ||
        current.ownerLane != MediaOwnerLane.group ||
        current.messageId != messageId ||
        current.downloadStatus != expectedDownloadStatus ||
        current.localPath != expectedLocalPath ||
        !const {
          kMediaDownloadStatusPending,
          kMediaDownloadStatusDownloading,
          kMediaDownloadStatusFailed,
          kMediaDownloadStatusDownloadFailed,
          kMediaDownloadStatusEvicted,
        }.contains(current.downloadStatus)) {
      return false;
    }
    _updateAttachment(
      id,
      (item) => item.copyWith(downloadStatus: kMediaDownloadStatusDownloading),
    );
    return true;
  }

  @override
  Future<bool> commitOrdinaryGroupExplicitMediaDownloadLocalPath(
    String id, {
    required String groupId,
    required String messageId,
    required String? expectedLocalPath,
    required String localPath,
  }) async {
    explicitCommitCalls += 1;
    await beforeExplicitCommit?.call(id);
    final current = _findAttachment(id);
    if (current == null ||
        !automaticParentPresent ||
        automaticParentLocallyDeleted ||
        (automaticParentGroupId != null && automaticParentGroupId != groupId) ||
        automaticDeletionJournaled ||
        current.ownerLane != MediaOwnerLane.group ||
        current.messageId != messageId ||
        current.downloadStatus != kMediaDownloadStatusDownloading ||
        current.localPath != expectedLocalPath) {
      return false;
    }
    _updateAttachment(
      id,
      (item) => item.copyWith(
        localPath: localPath,
        downloadStatus: kMediaDownloadStatusDone,
        downloadRetryCount: 0,
      ),
    );
    return true;
  }

  @override
  Future<int> claimMediaEvicted(
    String id, {
    required MediaOwnerLane owner,
    required String expectedLocalPath,
  }) async => 0;

  @override
  Future<int> finalizeMediaEvictedPathCleared(
    String id, {
    required MediaOwnerLane owner,
  }) async => 0;

  @override
  Future<bool> recordOrdinaryGroupMediaDownloadFailure(
    String id, {
    required String groupId,
    required String messageId,
    required bool incrementRetryCount,
    required String failureStatus,
    required String expectedDownloadStatus,
    required String? expectedLocalPath,
    required bool clearLocalPath,
  }) async {
    atomicFailureCalls.add((
      id: id,
      groupId: groupId,
      messageId: messageId,
      incrementRetryCount: incrementRetryCount,
      failureStatus: failureStatus,
      expectedDownloadStatus: expectedDownloadStatus,
      expectedLocalPath: expectedLocalPath,
      clearLocalPath: clearLocalPath,
    ));
    final current = _findAttachment(id);
    if (current == null ||
        current.ownerLane != MediaOwnerLane.group ||
        current.messageId != messageId ||
        current.downloadStatus != expectedDownloadStatus ||
        current.localPath != expectedLocalPath) {
      return false;
    }
    final nextRetryCount = incrementRetryCount
        ? (current.downloadRetryCount ?? 0) + 1
        : current.downloadRetryCount;
    final nextStatus = incrementRetryCount
        ? (nextRetryCount! >= kMaxDownloadRetries
              ? kMediaDownloadStatusDownloadFailed
              : kMediaDownloadStatusFailed)
        : failureStatus;
    _updateAttachment(
      id,
      (item) => item.copyWith(
        downloadStatus: nextStatus,
        downloadRetryCount: nextRetryCount,
        clearLocalPath: clearLocalPath,
      ),
    );
    return true;
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
    bool redactTelemetry = false,
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

/// 229: a file-manager fake whose ABSOLUTE paths follow the real
/// `media/<scope>/<blob><ext>` convention under [basePath], so the storage
/// manager (documents root = basePath) and the download use case address
/// the same canonical file.
class _CanonicalPathFakeMediaFileManager extends _FakeMediaFileManager {
  _CanonicalPathFakeMediaFileManager(super.basePath);

  @override
  Future<String> localPathForAttachment({
    required String contactPeerId,
    required String blobId,
    required String mime,
  }) async {
    final ext = _FakeMediaFileManager._extensionFromMime(mime);
    return '$basePath/media/$contactPeerId/$blobId$ext';
  }

  /// The private path guard needs a real containment root; path_provider is
  /// unavailable in host tests, so mirror the canonical convention root.
  @override
  Future<String> trustedMediaRootPath() async => '$basePath/media';
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
    _defaultDirectMessageRepo = _OrdinaryParentMessageRepository();
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
    test(
      'direct download with a missing current parent fails closed',
      () async {
        final result = await download_use_case.downloadMedia(
          owner: MediaOwnerLane.direct,
          bridge: bridge,
          mediaAttachmentRepo: mediaRepo,
          mediaFileManager: fileManager,
          attachment: testAttachment,
          contactPeerId: 'contact-A',
          messageRepo: InMemoryMessageRepository(),
          intent: MediaDownloadIntent.explicitUser,
        );

        expect(result, isNull);
        expect(bridge.commandLog, isEmpty);
        expect(mediaRepo.downloadStatusUpdates, isEmpty);
        expect(mediaRepo.localPathUpdates, isEmpty);
      },
    );

    test('production direct download call sites carry parent qualification', () {
      final sources = [
        File(
          'lib/features/conversation/application/chat_message_listener.dart',
        ).readAsStringSync(),
        File(
          'lib/features/conversation/presentation/screens/conversation_wired.dart',
        ).readAsStringSync(),
      ];
      final directCalls = RegExp(
        r'(?:downloadMedia|downloadMediaFn)\([\s\S]{0,900}?owner:\s*MediaOwnerLane\.direct,[\s\S]{0,300}?\)',
      );

      final matches = sources.expand(directCalls.allMatches).toList();
      expect(matches, isNotEmpty);
      for (final match in matches) {
        final call = match.group(0)!;
        expect(call, contains('messageRepo:'));
      }
    });

    test(
      'explicit available private parent reaches canonical durable storage',
      () async {
        final messageRepo = InMemoryMessageRepository();
        await messageRepo.saveMessage(
          ConversationMessage(
            id: testAttachment.messageId,
            contactPeerId: 'contact-A',
            senderPeerId: 'sender-A',
            text: '',
            timestamp: '2026-07-11T09:00:00.000Z',
            status: 'delivered',
            isIncoming: true,
            createdAt: '2026-07-11T09:00:00.000Z',
            privateMediaPolicy: const PrivateMediaPolicy.protected(),
            privateMediaState: PrivateMediaLifecycleState.available,
          ),
        );
        mediaRepo.seedAttachment(testAttachment);

        final result = await download_use_case.downloadMedia(
          owner: MediaOwnerLane.direct,
          bridge: bridge,
          mediaAttachmentRepo: mediaRepo,
          mediaFileManager: fileManager,
          attachment: testAttachment,
          contactPeerId: 'contact-A',
          messageRepo: messageRepo,
          intent: MediaDownloadIntent.explicitUser,
        );

        expect(result, isNotNull);
        expect(result!.downloadStatus, 'done');
        expect(result.localPath, isNotNull);
        expect(File(result.localPath!).existsSync(), isTrue);
        expect(bridge.commandLog, contains('media:download'));
        expect(mediaRepo.localPathUpdates, isNotEmpty);
      },
    );

    test(
      'unsupported parent denies explicit download before mutation',
      () async {
        final diagnostics = await AppDiagnostics.installForTesting();
        addTearDown(diagnostics.dispose);
        final messageRepo = InMemoryMessageRepository();
        await messageRepo.saveMessage(
          ConversationMessage(
            id: testAttachment.messageId,
            contactPeerId: 'contact-A',
            senderPeerId: 'sender-A',
            text: '',
            timestamp: '2026-07-11T09:00:00.000Z',
            status: 'delivered',
            isIncoming: true,
            createdAt: '2026-07-11T09:00:00.000Z',
            privateMediaPolicy: const PrivateMediaPolicy.unsupported(
              sourceVersion: 9,
            ),
            privateMediaState: PrivateMediaLifecycleState.unsupported,
          ),
        );

        final result = await download_use_case.downloadMedia(
          owner: MediaOwnerLane.direct,
          bridge: bridge,
          mediaAttachmentRepo: mediaRepo,
          mediaFileManager: fileManager,
          attachment: testAttachment,
          contactPeerId: 'contact-A',
          messageRepo: messageRepo,
          intent: MediaDownloadIntent.explicitUser,
        );

        expect(result, isNull);
        expect(bridge.commandLog, isEmpty);
        expect(mediaRepo.downloadStatusUpdates, isEmpty);
        expect(mediaRepo.localPathUpdates, isEmpty);
        final events = (await diagnostics.eventsForTesting())
            .where((e) => e['feature'] == 'media')
            .toList();
        expect(events.last['reason'], 'unsupported');
        expect(
          events.where(
            (e) => e['stage'] == 'download' || e['stage'] == 'decrypt',
          ),
          isEmpty,
        );
      },
    );

    test(
      'terminal private parent denies before bridge or row mutation',
      () async {
        final messageRepo = InMemoryMessageRepository();
        final policy = PrivateMediaPolicy.fromJson(const {
          'version': 1,
          'mode': 'view_once',
        });
        await messageRepo.saveMessage(
          ConversationMessage(
            id: testAttachment.messageId,
            contactPeerId: 'contact-A',
            senderPeerId: 'sender-A',
            text: '',
            timestamp: '2026-07-11T09:00:00.000Z',
            status: 'delivered',
            isIncoming: true,
            createdAt: '2026-07-11T09:00:00.000Z',
            privateMediaPolicy: policy,
            privateMediaState: PrivateMediaLifecycleState.consumed,
          ),
        );

        final result = await downloadMedia(
          owner: MediaOwnerLane.direct,
          bridge: bridge,
          mediaAttachmentRepo: mediaRepo,
          mediaFileManager: fileManager,
          attachment: testAttachment,
          contactPeerId: 'contact-A',
          messageRepo: messageRepo,
          intent: MediaDownloadIntent.explicitUser,
        );

        expect(result, isNull);
        expect(bridge.sendCallCount, 0);
        expect(bridge.commandLog, isEmpty);
        expect(mediaRepo.downloadStatusUpdates, isEmpty);
        expect(mediaRepo.localPathUpdates, isEmpty);
      },
    );

    test(
      'hidden deleted and corrupt parents deny before bridge or row mutation',
      () async {
        final parents = <ConversationMessage>[
          ConversationMessage(
            id: testAttachment.messageId,
            contactPeerId: 'contact-A',
            senderPeerId: 'sender-A',
            text: '',
            timestamp: '2026-07-11T09:00:00.000Z',
            status: 'delivered',
            isIncoming: true,
            createdAt: '2026-07-11T09:00:00.000Z',
            hiddenAt: '2026-07-11T09:01:00.000Z',
          ),
          ConversationMessage(
            id: testAttachment.messageId,
            contactPeerId: 'contact-A',
            senderPeerId: 'sender-A',
            text: '',
            timestamp: '2026-07-11T09:00:00.000Z',
            status: 'delivered',
            isIncoming: true,
            createdAt: '2026-07-11T09:00:00.000Z',
            deletedAt: '2026-07-11T09:01:00.000Z',
          ),
          ConversationMessage(
            id: testAttachment.messageId,
            contactPeerId: 'contact-A',
            senderPeerId: 'sender-A',
            text: '',
            timestamp: '2026-07-11T09:00:00.000Z',
            status: 'delivered',
            isIncoming: true,
            createdAt: '2026-07-11T09:00:00.000Z',
            privateMediaPolicy: const PrivateMediaPolicy.protected(),
            privateMediaState: PrivateMediaLifecycleState.none,
          ),
        ];

        for (final currentParent in parents) {
          final messageRepo = InMemoryMessageRepository();
          await messageRepo.saveMessage(currentParent);
          final result = await downloadMedia(
            owner: MediaOwnerLane.direct,
            bridge: bridge,
            mediaAttachmentRepo: mediaRepo,
            mediaFileManager: fileManager,
            attachment: testAttachment,
            contactPeerId: 'contact-A',
            messageRepo: messageRepo,
            intent: MediaDownloadIntent.explicitUser,
          );
          expect(result, isNull);
        }
        expect(bridge.sendCallCount, 0);
        expect(bridge.commandLog, isEmpty);
        expect(mediaRepo.downloadStatusUpdates, isEmpty);
        expect(mediaRepo.localPathUpdates, isEmpty);
      },
    );

    test(
      'private explicit download never joins or races an ordinary unguarded future',
      () async {
        final delayedBridge = _DelayedBridge();
        final messageRepo = InMemoryMessageRepository();
        await messageRepo.saveMessage(
          ConversationMessage(
            id: testAttachment.messageId,
            contactPeerId: 'contact-A',
            senderPeerId: 'sender-A',
            text: '',
            timestamp: '2026-07-11T09:00:00.000Z',
            status: 'delivered',
            isIncoming: true,
            createdAt: '2026-07-11T09:00:00.000Z',
          ),
        );
        mediaRepo.seedAttachment(testAttachment);
        final ordinaryFuture = downloadMedia(
          owner: MediaOwnerLane.direct,
          bridge: delayedBridge,
          mediaAttachmentRepo: mediaRepo,
          mediaFileManager: fileManager,
          attachment: testAttachment,
          contactPeerId: 'contact-A',
          messageRepo: messageRepo,
          intent: MediaDownloadIntent.explicitUser,
        );
        for (
          var attempt = 0;
          attempt < 100 && delayedBridge.sendCallCount < 1;
          attempt++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
        expect(delayedBridge.sendCallCount, 1);

        await messageRepo.saveMessage(
          ConversationMessage(
            id: testAttachment.messageId,
            contactPeerId: 'contact-A',
            senderPeerId: 'sender-A',
            text: '',
            timestamp: '2026-07-11T09:00:00.000Z',
            status: 'delivered',
            isIncoming: true,
            createdAt: '2026-07-11T09:00:00.000Z',
            privateMediaPolicy: const PrivateMediaPolicy.protected(),
            privateMediaState: PrivateMediaLifecycleState.available,
          ),
        );
        // Simulate a replay/transition restoring the exact current row while
        // the earlier ordinary transfer is still pending.
        mediaRepo.seedAttachment(testAttachment);
        final privateFuture = downloadMedia(
          owner: MediaOwnerLane.direct,
          bridge: delayedBridge,
          mediaAttachmentRepo: mediaRepo,
          mediaFileManager: fileManager,
          attachment: testAttachment,
          contactPeerId: 'contact-A',
          messageRepo: messageRepo,
          intent: MediaDownloadIntent.explicitUser,
        );
        for (
          var attempt = 0;
          attempt < 100 && delayedBridge.sendCallCount < 2;
          attempt++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }

        final callCountBeforeRelease = delayedBridge.sendCallCount;
        delayedBridge.gate.complete();
        final outcomes = await Future.wait([ordinaryFuture, privateFuture]);
        expect(callCountBeforeRelease, 1);
        expect(outcomes.first, isNotNull);
        expect(outcomes.last, isNull);
      },
    );

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
      'P269 ordinary group transient failure uses one atomic retry transition while relay authorization denial stays terminal',
      () async {
        const groupId = 'group-p269-atomic';
        final groupRepo = InMemoryGroupMessageRepository();
        await groupRepo.saveMessage(
          GroupMessage(
            id: testAttachment.messageId,
            groupId: groupId,
            senderPeerId: 'sender-p269',
            text: '',
            timestamp: DateTime.utc(2026, 7, 22, 12),
            status: 'delivered',
            isIncoming: true,
            createdAt: DateTime.utc(2026, 7, 22, 12),
          ),
        );
        final atomicRepo = _AtomicOrdinaryGroupFailureMediaRepo();
        final events = <Map<String, dynamic>>[];
        debugSetFlowEventSink(events.add);
        addTearDown(() => debugSetFlowEventSink(null));

        MediaAttachment groupAttachment({
          required String id,
          int retryCount = 0,
          String? contentHash,
        }) => _encryptedGroupAttachment(
          testAttachment.copyWith(
            id: id,
            ownerLane: MediaOwnerLane.group,
            downloadRetryCount: retryCount,
          ),
          _jpegBytes,
          contentHash: contentHash,
        );

        Future<MediaAttachment> stored(String id) async =>
            (await atomicRepo.getAttachmentsForMessage(
              testAttachment.messageId,
              owner: MediaOwnerLane.group,
            )).singleWhere((attachment) => attachment.id == id);

        final transient = groupAttachment(id: 'p269-transient');
        atomicRepo.seedAttachment(transient);
        bridge.downloadResponse = {
          'ok': false,
          'errorMessage': 'relay temporarily unavailable',
        };
        expect(
          await downloadMedia(
            owner: MediaOwnerLane.group,
            bridge: bridge,
            mediaAttachmentRepo: atomicRepo,
            mediaFileManager: fileManager,
            attachment: transient,
            contactPeerId: groupId,
            groupMessageRepo: groupRepo,
            enforceGroupMediaPolicy: true,
          ),
          isNull,
        );
        var persisted = await stored(transient.id);
        expect(persisted.downloadStatus, kMediaDownloadStatusFailed);
        expect(persisted.downloadRetryCount, 1);
        expect(atomicRepo.atomicFailureCalls, hasLength(1));
        expect(atomicRepo.atomicFailureCalls.single, (
          id: transient.id,
          groupId: groupId,
          messageId: transient.messageId,
          incrementRetryCount: true,
          failureStatus: kMediaDownloadStatusFailed,
          expectedDownloadStatus: kMediaDownloadStatusDownloading,
          expectedLocalPath: null,
          clearLocalPath: false,
        ));

        final unauthorized = groupAttachment(
          id: 'p269-unauthorized',
          retryCount: 2,
        );
        atomicRepo.seedAttachment(unauthorized);
        bridge.downloadResponse = {
          'ok': false,
          'errorMessage': 'not authorized',
        };
        expect(
          await downloadMedia(
            owner: MediaOwnerLane.group,
            bridge: bridge,
            mediaAttachmentRepo: atomicRepo,
            mediaFileManager: fileManager,
            attachment: unauthorized,
            contactPeerId: groupId,
            groupMessageRepo: groupRepo,
            enforceGroupMediaPolicy: true,
          ),
          isNull,
        );
        persisted = await stored(unauthorized.id);
        expect(persisted.downloadStatus, kMediaDownloadStatusDownloadFailed);
        expect(
          persisted.downloadRetryCount,
          2,
          reason: 'relay authorization denial consumes no retry budget',
        );
        expect(atomicRepo.atomicFailureCalls, hasLength(2));
        expect(atomicRepo.atomicFailureCalls.last.incrementRetryCount, isFalse);
        expect(
          atomicRepo.atomicFailureCalls.last.failureStatus,
          kMediaDownloadStatusDownloadFailed,
        );
        expect(
          events.where(
            (event) =>
                event['event'] == 'MEDIA_DOWNLOAD_FAILED' &&
                (event['details'] as Map<String, dynamic>)['error'] ==
                    'not authorized',
          ),
          hasLength(1),
          reason: 'denial stays the generic truthful relay reason',
        );

        final notFound = groupAttachment(id: 'p269-not-found', retryCount: 1);
        atomicRepo.seedAttachment(notFound);
        bridge.downloadResponse = {'ok': false, 'errorMessage': 'not found'};
        expect(
          await downloadMedia(
            owner: MediaOwnerLane.group,
            bridge: bridge,
            mediaAttachmentRepo: atomicRepo,
            mediaFileManager: fileManager,
            attachment: notFound,
            contactPeerId: groupId,
            groupMessageRepo: groupRepo,
            enforceGroupMediaPolicy: true,
          ),
          isNull,
        );
        persisted = await stored(notFound.id);
        expect(persisted.downloadStatus, kMediaDownloadStatusDownloadFailed);
        expect(
          persisted.downloadRetryCount,
          1,
          reason: 'relay not-found consumes no retry budget',
        );
        expect(atomicRepo.atomicFailureCalls, hasLength(3));
        expect(atomicRepo.atomicFailureCalls.last, (
          id: notFound.id,
          groupId: groupId,
          messageId: notFound.messageId,
          incrementRetryCount: false,
          failureStatus: kMediaDownloadStatusDownloadFailed,
          expectedDownloadStatus: kMediaDownloadStatusDownloading,
          expectedLocalPath: null,
          clearLocalPath: false,
        ));
        expect(
          events.where(
            (event) =>
                event['event'] == 'MEDIA_DOWNLOAD_FAILED' &&
                (event['details'] as Map<String, dynamic>)['error'] ==
                    'not found',
          ),
          hasLength(1),
        );

        final corrupt = groupAttachment(
          id: 'p269-integrity',
          contentHash:
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        ).copyWith(clearEncryptionKeyBase64: true);
        atomicRepo.seedAttachment(corrupt);
        final sendsBeforeIntegrity = bridge.sendCallCount;
        expect(
          await downloadMedia(
            owner: MediaOwnerLane.group,
            bridge: bridge,
            mediaAttachmentRepo: atomicRepo,
            mediaFileManager: fileManager,
            attachment: corrupt,
            contactPeerId: groupId,
            groupMessageRepo: groupRepo,
            enforceGroupMediaPolicy: true,
          ),
          isNull,
        );
        persisted = await stored(corrupt.id);
        expect(persisted.downloadStatus, kMediaDownloadStatusIntegrityFailed);
        expect(persisted.downloadRetryCount, 0);
        expect(bridge.sendCallCount, sendsBeforeIntegrity);
        expect(atomicRepo.atomicFailureCalls, hasLength(4));
        expect(atomicRepo.atomicFailureCalls.last, (
          id: corrupt.id,
          groupId: groupId,
          messageId: corrupt.messageId,
          incrementRetryCount: false,
          failureStatus: kMediaDownloadStatusIntegrityFailed,
          expectedDownloadStatus: kMediaDownloadStatusPending,
          expectedLocalPath: null,
          clearLocalPath: true,
        ));

        final encrypted = _encryptedBytes(_jpegBytes);
        final hashMismatch = groupAttachment(
          id: 'p269-post-download-integrity',
          retryCount: 2,
          contentHash:
              'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        );
        atomicRepo.seedAttachment(hashMismatch);
        bridge.downloadedBytes = encrypted;
        bridge.downloadResponse = {
          'ok': true,
          'id': hashMismatch.id,
          'mime': 'image/jpeg',
          'size': encrypted.length,
        };
        final sendsBeforeHashMismatch = bridge.sendCallCount;
        expect(
          await downloadMedia(
            owner: MediaOwnerLane.group,
            bridge: bridge,
            mediaAttachmentRepo: atomicRepo,
            mediaFileManager: fileManager,
            attachment: hashMismatch,
            contactPeerId: groupId,
            groupMessageRepo: groupRepo,
            enforceGroupMediaPolicy: true,
          ),
          isNull,
        );
        persisted = await stored(hashMismatch.id);
        expect(persisted.downloadStatus, kMediaDownloadStatusIntegrityFailed);
        expect(
          persisted.downloadRetryCount,
          2,
          reason: 'post-download integrity quarantine consumes no retry budget',
        );
        expect(bridge.sendCallCount, sendsBeforeHashMismatch + 1);
        expect(atomicRepo.atomicFailureCalls, hasLength(5));
        expect(atomicRepo.atomicFailureCalls.last, (
          id: hashMismatch.id,
          groupId: groupId,
          messageId: hashMismatch.messageId,
          incrementRetryCount: false,
          failureStatus: kMediaDownloadStatusIntegrityFailed,
          expectedDownloadStatus: kMediaDownloadStatusDownloading,
          expectedLocalPath: null,
          clearLocalPath: true,
        ));
        final hashMismatchOutputPath =
            (bridge.lastRequest!['payload']
                    as Map<String, dynamic>)['outputPath']
                as String;
        expect(File(hashMismatchOutputPath).existsSync(), isFalse);

        expect(atomicRepo.downloadStatusUpdates, isEmpty);
        expect(atomicRepo.legacySaveCalls, 0);
        expect(bridge.deleteRequests, isEmpty);
      },
    );

    test(
      'P269 automatic ordinary group lost terminal or evicted claim performs zero bridge calls',
      () async {
        const groupId = 'group-p269-automatic-claim';
        final groupRepo = InMemoryGroupMessageRepository();
        await groupRepo.saveMessage(
          GroupMessage(
            id: testAttachment.messageId,
            groupId: groupId,
            senderPeerId: 'sender-p269',
            text: '',
            timestamp: DateTime.utc(2026, 7, 22, 13),
            status: 'delivered',
            isIncoming: true,
            createdAt: DateTime.utc(2026, 7, 22, 13),
          ),
        );

        for (final terminalStatus in const <String>[
          kMediaDownloadStatusDownloadFailed,
          kMediaDownloadStatusEvicted,
        ]) {
          final attachment = _encryptedGroupAttachment(
            testAttachment.copyWith(
              id: 'p269-raced-$terminalStatus',
              ownerLane: MediaOwnerLane.group,
              downloadRetryCount: 0,
            ),
            _jpegBytes,
          );
          final repository = _AtomicOrdinaryGroupFailureMediaRepo()
            ..seedAttachment(attachment);
          repository.beforeAutomaticBegin = (id) {
            repository._updateAttachment(
              id,
              (current) => current.copyWith(
                downloadStatus: terminalStatus,
                downloadRetryCount:
                    terminalStatus == kMediaDownloadStatusDownloadFailed
                    ? kMaxDownloadRetries
                    : current.downloadRetryCount,
              ),
            );
          };
          final sendsBefore = bridge.sendCallCount;

          expect(
            await downloadMedia(
              owner: MediaOwnerLane.group,
              bridge: bridge,
              mediaAttachmentRepo: repository,
              mediaFileManager: fileManager,
              attachment: attachment,
              contactPeerId: groupId,
              groupMessageRepo: groupRepo,
              enforceGroupMediaPolicy: true,
            ),
            isNull,
          );
          expect(
            bridge.sendCallCount,
            sendsBefore,
            reason: '$terminalStatus must lose before bridge access',
          );
          final persisted = (await repository.getAttachmentsForMessage(
            attachment.messageId,
            owner: MediaOwnerLane.group,
          )).single;
          expect(persisted.downloadStatus, terminalStatus);
          expect(repository.atomicFailureCalls, isEmpty);
        }
      },
    );

    test(
      'P269 automatic ordinary group encrypted companion uses exact begin and commit authority without relay',
      () async {
        const groupId = 'group-p269-companion-success';
        final groupRepo = InMemoryGroupMessageRepository();
        await groupRepo.saveMessage(
          GroupMessage(
            id: testAttachment.messageId,
            groupId: groupId,
            senderPeerId: 'sender-p269',
            text: '',
            timestamp: DateTime.utc(2026, 7, 22, 15),
            status: 'delivered',
            isIncoming: true,
            createdAt: DateTime.utc(2026, 7, 22, 15),
          ),
        );
        final attachment = _encryptedGroupAttachment(
          testAttachment.copyWith(
            id: 'p269-companion-success',
            ownerLane: MediaOwnerLane.group,
          ),
          _jpegBytes,
        );
        final repository = _AtomicOrdinaryGroupFailureMediaRepo()
          ..seedAttachment(attachment);
        final absolutePath = await fileManager.localPathForAttachment(
          contactPeerId: groupId,
          blobId: attachment.id,
          mime: attachment.mime,
        );
        final encryptedCompanion = File('$absolutePath.enc');
        await encryptedCompanion.parent.create(recursive: true);
        await encryptedCompanion.writeAsBytes(
          _encryptedBytes(_jpegBytes),
          flush: true,
        );

        final result = await downloadMedia(
          owner: MediaOwnerLane.group,
          bridge: bridge,
          mediaAttachmentRepo: repository,
          mediaFileManager: fileManager,
          attachment: attachment,
          contactPeerId: groupId,
          groupMessageRepo: groupRepo,
          enforceGroupMediaPolicy: true,
        );

        expect(result, isNotNull);
        expect(result!.localPath, absolutePath);
        expect(result.downloadStatus, kMediaDownloadStatusDone);
        expect(repository.automaticBeginCalls, 1);
        expect(repository.automaticCommitCalls, 1);
        expect(repository.localPathUpdates, isEmpty);
        expect(repository.legacySaveCalls, 0);
        expect(bridge.commandLog, equals(<String>['blob:decrypt']));
        expect(File(absolutePath).readAsBytesSync(), _jpegBytes);
        expect(encryptedCompanion.existsSync(), isFalse);
        final stored = (await repository.getAttachmentsForMessage(
          attachment.messageId,
          owner: MediaOwnerLane.group,
        )).single;
        expect(stored.localPath, 'media/$groupId/${attachment.id}.jpg');
        expect(stored.downloadStatus, kMediaDownloadStatusDone);
      },
    );

    test(
      'P269 automatic ordinary group companion loses before decrypt to delete-for-me or parent-group races',
      () async {
        const groupId = 'group-p269-companion-begin';
        for (final race in const <String>['delete_for_me', 'parent_group']) {
          final groupRepo = InMemoryGroupMessageRepository();
          GroupMessage parent(String parentGroupId) => GroupMessage(
            id: testAttachment.messageId,
            groupId: parentGroupId,
            senderPeerId: 'sender-p269',
            text: '',
            timestamp: DateTime.utc(2026, 7, 22, 16),
            status: 'delivered',
            isIncoming: true,
            createdAt: DateTime.utc(2026, 7, 22, 16),
          );
          await groupRepo.saveMessage(parent(groupId));
          final attachment = _encryptedGroupAttachment(
            testAttachment.copyWith(
              id: 'p269-companion-$race',
              ownerLane: MediaOwnerLane.group,
            ),
            _jpegBytes,
          );
          final repository = _AtomicOrdinaryGroupFailureMediaRepo()
            ..seedAttachment(attachment);
          repository.beforeAutomaticBegin = (_) async {
            if (race == 'delete_for_me') {
              await groupRepo.deleteMessage(attachment.messageId);
              repository.automaticParentLocallyDeleted = true;
            } else {
              const replacementGroupId = 'group-p269-reassigned';
              await groupRepo.saveMessage(parent(replacementGroupId));
              repository.automaticParentGroupId = replacementGroupId;
            }
          };
          final absolutePath = await fileManager.localPathForAttachment(
            contactPeerId: groupId,
            blobId: attachment.id,
            mime: attachment.mime,
          );
          final encryptedCompanion = File('$absolutePath.enc');
          await encryptedCompanion.parent.create(recursive: true);
          await encryptedCompanion.writeAsBytes(
            _encryptedBytes(_jpegBytes),
            flush: true,
          );
          final raceBridge = _FakeBridge();

          final result = await downloadMedia(
            owner: MediaOwnerLane.group,
            bridge: raceBridge,
            mediaAttachmentRepo: repository,
            mediaFileManager: fileManager,
            attachment: attachment,
            contactPeerId: groupId,
            groupMessageRepo: groupRepo,
            enforceGroupMediaPolicy: true,
          );

          expect(result, isNull, reason: race);
          expect(repository.automaticBeginCalls, 1, reason: race);
          expect(repository.automaticCommitCalls, 0, reason: race);
          expect(raceBridge.commandLog, isEmpty, reason: race);
          expect(File(absolutePath).existsSync(), isFalse, reason: race);
          expect(encryptedCompanion.existsSync(), isTrue, reason: race);
          expect(repository.localPathUpdates, isEmpty, reason: race);
          final stored = (await repository.getAttachmentsForMessage(
            attachment.messageId,
            owner: MediaOwnerLane.group,
          )).single;
          expect(stored.downloadStatus, attachment.downloadStatus);
          expect(stored.localPath, attachment.localPath);
        }
      },
    );

    test(
      'P269 deletion-journal race loses companion commit, removes only new plaintext, and publishes nothing',
      () async {
        const groupId = 'group-p269-companion-journal';
        final groupRepo = InMemoryGroupMessageRepository();
        await groupRepo.saveMessage(
          GroupMessage(
            id: testAttachment.messageId,
            groupId: groupId,
            senderPeerId: 'sender-p269',
            text: '',
            timestamp: DateTime.utc(2026, 7, 22, 17),
            status: 'delivered',
            isIncoming: true,
            createdAt: DateTime.utc(2026, 7, 22, 17),
          ),
        );
        final attachment = _encryptedGroupAttachment(
          testAttachment.copyWith(
            id: 'p269-companion-journal',
            ownerLane: MediaOwnerLane.group,
          ),
          _jpegBytes,
        );
        final repository = _AtomicOrdinaryGroupFailureMediaRepo()
          ..seedAttachment(attachment);
        repository.beforeAutomaticCommit = (_) {
          repository.automaticDeletionJournaled = true;
        };
        final absolutePath = await fileManager.localPathForAttachment(
          contactPeerId: groupId,
          blobId: attachment.id,
          mime: attachment.mime,
        );
        final encryptedCompanion = File('$absolutePath.enc');
        await encryptedCompanion.parent.create(recursive: true);
        final encryptedBytes = _encryptedBytes(_jpegBytes);
        await encryptedCompanion.writeAsBytes(encryptedBytes, flush: true);
        final siblingPath = await fileManager.localPathForAttachment(
          contactPeerId: groupId,
          blobId: 'p269-companion-sibling',
          mime: attachment.mime,
        );
        final sibling = File(siblingPath);
        await sibling.writeAsBytes(const <int>[7, 8, 9], flush: true);
        final events = <Map<String, dynamic>>[];
        debugSetFlowEventSink(events.add);
        addTearDown(() => debugSetFlowEventSink(null));

        final result = await downloadMedia(
          owner: MediaOwnerLane.group,
          bridge: bridge,
          mediaAttachmentRepo: repository,
          mediaFileManager: fileManager,
          attachment: attachment,
          contactPeerId: groupId,
          groupMessageRepo: groupRepo,
          enforceGroupMediaPolicy: true,
        );

        expect(result, isNull);
        expect(repository.automaticBeginCalls, 1);
        expect(repository.automaticCommitCalls, 1);
        expect(bridge.commandLog, equals(<String>['blob:decrypt']));
        expect(File(absolutePath).existsSync(), isFalse);
        expect(encryptedCompanion.readAsBytesSync(), encryptedBytes);
        expect(sibling.readAsBytesSync(), const <int>[7, 8, 9]);
        expect(repository.localPathUpdates, isEmpty);
        expect(repository.atomicFailureCalls, isEmpty);
        final stored = (await repository.getAttachmentsForMessage(
          attachment.messageId,
          owner: MediaOwnerLane.group,
        )).single;
        expect(stored.downloadStatus, kMediaDownloadStatusDownloading);
        expect(stored.localPath, isNull);
        final eventNames = events.map((event) => event['event']).toList();
        expect(eventNames, contains('MEDIA_DOWNLOAD_CLAIM_LOST'));
        expect(
          eventNames,
          isNot(
            contains('MEDIA_DOWNLOAD_REPAIRED_FROM_LOCAL_ENCRYPTED_COMPANION'),
          ),
        );
        expect(
          eventNames,
          isNot(contains('MEDIA_DOWNLOAD_DURABLE_LOCAL_PATH_COMMITTED')),
        );
        expect(
          eventNames,
          isNot(contains('MEDIA_GROUP_DURABLE_LOCAL_PATH_DELAYED_PROBE')),
        );
      },
    );

    test(
      'P269 explicit ordinary group companion preserves broad terminal retry semantics with exact authority',
      () async {
        const groupId = 'group-p269-explicit-companion-success';
        final groupRepo = InMemoryGroupMessageRepository();
        await groupRepo.saveMessage(
          GroupMessage(
            id: testAttachment.messageId,
            groupId: groupId,
            senderPeerId: 'sender-p269',
            text: '',
            timestamp: DateTime.utc(2026, 7, 22, 18),
            status: 'delivered',
            isIncoming: true,
            createdAt: DateTime.utc(2026, 7, 22, 18),
          ),
        );

        for (final terminalStatus in const <String>[
          kMediaDownloadStatusDownloadFailed,
          kMediaDownloadStatusEvicted,
        ]) {
          final attachment = _encryptedGroupAttachment(
            testAttachment.copyWith(
              id: 'p269-explicit-companion-$terminalStatus',
              ownerLane: MediaOwnerLane.group,
              downloadStatus: terminalStatus,
              downloadRetryCount: kMaxDownloadRetries,
            ),
            _jpegBytes,
          );
          final repository = _AtomicOrdinaryGroupFailureMediaRepo()
            ..seedAttachment(attachment);
          final absolutePath = await fileManager.localPathForAttachment(
            contactPeerId: groupId,
            blobId: attachment.id,
            mime: attachment.mime,
          );
          final encryptedCompanion = File('$absolutePath.enc');
          await encryptedCompanion.parent.create(recursive: true);
          await encryptedCompanion.writeAsBytes(
            _encryptedBytes(_jpegBytes),
            flush: true,
          );
          final explicitBridge = _FakeBridge();

          final result = await downloadMedia(
            owner: MediaOwnerLane.group,
            bridge: explicitBridge,
            mediaAttachmentRepo: repository,
            mediaFileManager: fileManager,
            attachment: attachment,
            contactPeerId: groupId,
            groupMessageRepo: groupRepo,
            intent: MediaDownloadIntent.explicitUser,
            enforceGroupMediaPolicy: true,
          );

          expect(result, isNotNull, reason: terminalStatus);
          expect(result!.localPath, absolutePath, reason: terminalStatus);
          expect(
            result.downloadStatus,
            kMediaDownloadStatusDone,
            reason: terminalStatus,
          );
          expect(repository.explicitBeginCalls, 1, reason: terminalStatus);
          expect(repository.explicitCommitCalls, 1, reason: terminalStatus);
          expect(repository.automaticBeginCalls, 0, reason: terminalStatus);
          expect(repository.automaticCommitCalls, 0, reason: terminalStatus);
          expect(repository.localPathUpdates, isEmpty, reason: terminalStatus);
          expect(repository.legacySaveCalls, 0, reason: terminalStatus);
          expect(
            explicitBridge.commandLog,
            equals(<String>['blob:decrypt']),
            reason: terminalStatus,
          );
          expect(File(absolutePath).readAsBytesSync(), _jpegBytes);
          expect(encryptedCompanion.existsSync(), isFalse);
          final stored = (await repository.getAttachmentsForMessage(
            attachment.messageId,
            owner: MediaOwnerLane.group,
          )).single;
          expect(
            stored.localPath,
            'media/$groupId/${attachment.id}.jpg',
            reason: terminalStatus,
          );
          expect(
            stored.downloadStatus,
            kMediaDownloadStatusDone,
            reason: terminalStatus,
          );
        }
      },
    );

    test(
      'P269 explicit ordinary group stale done path clears exactly then relays and commits exactly',
      () async {
        const groupId = 'group-p269-explicit-stale-done';
        final groupRepo = InMemoryGroupMessageRepository();
        await groupRepo.saveMessage(
          GroupMessage(
            id: testAttachment.messageId,
            groupId: groupId,
            senderPeerId: 'sender-p269',
            text: '',
            timestamp: DateTime.utc(2026, 7, 22, 18, 30),
            status: 'delivered',
            isIncoming: true,
            createdAt: DateTime.utc(2026, 7, 22, 18, 30),
          ),
        );
        const staleRelativePath =
            'media/group-p269-explicit-stale-done/p269-explicit-stale-done.jpg';
        final attachment = _encryptedGroupAttachment(
          testAttachment.copyWith(
            id: 'p269-explicit-stale-done',
            ownerLane: MediaOwnerLane.group,
            downloadStatus: kMediaDownloadStatusDone,
            localPath: staleRelativePath,
          ),
          _jpegBytes,
        );
        final repository = _AtomicOrdinaryGroupFailureMediaRepo()
          ..seedAttachment(attachment);
        final encrypted = _encryptedBytes(_jpegBytes);
        final explicitBridge = _FakeBridge()
          ..downloadedBytes = encrypted
          ..downloadResponse = <String, dynamic>{
            'ok': true,
            'id': attachment.id,
            'mime': attachment.mime,
            'size': encrypted.length,
          };
        final staleAbsolutePath = await fileManager.resolveStoredPath(
          staleRelativePath,
        );
        final absolutePath = await fileManager.localPathForAttachment(
          contactPeerId: groupId,
          blobId: attachment.id,
          mime: attachment.mime,
        );
        expect(File(staleAbsolutePath).existsSync(), isFalse);
        expect(File(absolutePath).existsSync(), isFalse);

        final result = await downloadMedia(
          owner: MediaOwnerLane.group,
          bridge: explicitBridge,
          mediaAttachmentRepo: repository,
          mediaFileManager: fileManager,
          attachment: attachment,
          contactPeerId: groupId,
          groupMessageRepo: groupRepo,
          intent: MediaDownloadIntent.explicitUser,
          enforceGroupMediaPolicy: true,
        );

        expect(result, isNotNull);
        expect(result!.downloadStatus, kMediaDownloadStatusDone);
        expect(result.localPath, absolutePath);
        expect(repository.atomicFailureCalls, hasLength(1));
        final staleClear = repository.atomicFailureCalls.single;
        expect(staleClear.incrementRetryCount, isFalse);
        expect(staleClear.failureStatus, kMediaDownloadStatusFailed);
        expect(staleClear.expectedDownloadStatus, kMediaDownloadStatusDone);
        expect(staleClear.expectedLocalPath, staleRelativePath);
        expect(staleClear.clearLocalPath, isTrue);
        expect(repository.explicitBeginCalls, 1);
        expect(repository.explicitCommitCalls, 1);
        expect(repository.automaticBeginCalls, 0);
        expect(repository.automaticCommitCalls, 0);
        expect(repository.localPathUpdates, isEmpty);
        expect(repository.legacySaveCalls, 0);
        expect(
          explicitBridge.commandLog.where(
            (command) => command == 'media:download',
          ),
          hasLength(1),
        );
        expect(
          explicitBridge.commandLog.where(
            (command) => command == 'blob:decrypt',
          ),
          hasLength(1),
        );
        expect(File(absolutePath).readAsBytesSync(), _jpegBytes);
        final stored = (await repository.getAttachmentsForMessage(
          attachment.messageId,
          owner: MediaOwnerLane.group,
        )).single;
        expect(stored.downloadStatus, kMediaDownloadStatusDone);
        expect(stored.localPath, staleRelativePath);
      },
    );

    test(
      'P269 explicit ordinary group companion loses before decrypt to delete-for-me or parent-group races',
      () async {
        const groupId = 'group-p269-explicit-companion-begin';
        for (final race in const <String>['delete_for_me', 'parent_group']) {
          final groupRepo = InMemoryGroupMessageRepository();
          GroupMessage parent(String parentGroupId) => GroupMessage(
            id: testAttachment.messageId,
            groupId: parentGroupId,
            senderPeerId: 'sender-p269',
            text: '',
            timestamp: DateTime.utc(2026, 7, 22, 19),
            status: 'delivered',
            isIncoming: true,
            createdAt: DateTime.utc(2026, 7, 22, 19),
          );
          await groupRepo.saveMessage(parent(groupId));
          final attachment = _encryptedGroupAttachment(
            testAttachment.copyWith(
              id: 'p269-explicit-companion-$race',
              ownerLane: MediaOwnerLane.group,
              downloadStatus: kMediaDownloadStatusDownloadFailed,
              downloadRetryCount: kMaxDownloadRetries,
            ),
            _jpegBytes,
          );
          final repository = _AtomicOrdinaryGroupFailureMediaRepo()
            ..seedAttachment(attachment);
          repository.beforeExplicitBegin = (_) async {
            if (race == 'delete_for_me') {
              await groupRepo.deleteMessage(attachment.messageId);
              repository.automaticParentLocallyDeleted = true;
            } else {
              const replacementGroupId = 'group-p269-explicit-reassigned';
              await groupRepo.saveMessage(parent(replacementGroupId));
              repository.automaticParentGroupId = replacementGroupId;
            }
          };
          final absolutePath = await fileManager.localPathForAttachment(
            contactPeerId: groupId,
            blobId: attachment.id,
            mime: attachment.mime,
          );
          final encryptedCompanion = File('$absolutePath.enc');
          await encryptedCompanion.parent.create(recursive: true);
          final encryptedBytes = _encryptedBytes(_jpegBytes);
          await encryptedCompanion.writeAsBytes(encryptedBytes, flush: true);
          final raceBridge = _FakeBridge();

          final result = await downloadMedia(
            owner: MediaOwnerLane.group,
            bridge: raceBridge,
            mediaAttachmentRepo: repository,
            mediaFileManager: fileManager,
            attachment: attachment,
            contactPeerId: groupId,
            groupMessageRepo: groupRepo,
            intent: MediaDownloadIntent.explicitUser,
            enforceGroupMediaPolicy: true,
          );

          expect(result, isNull, reason: race);
          expect(repository.explicitBeginCalls, 1, reason: race);
          expect(repository.explicitCommitCalls, 0, reason: race);
          expect(repository.automaticBeginCalls, 0, reason: race);
          expect(repository.automaticCommitCalls, 0, reason: race);
          expect(raceBridge.commandLog, isEmpty, reason: race);
          expect(File(absolutePath).existsSync(), isFalse, reason: race);
          expect(
            encryptedCompanion.readAsBytesSync(),
            encryptedBytes,
            reason: race,
          );
          expect(repository.localPathUpdates, isEmpty, reason: race);
          final stored = (await repository.getAttachmentsForMessage(
            attachment.messageId,
            owner: MediaOwnerLane.group,
          )).single;
          expect(
            stored.downloadStatus,
            kMediaDownloadStatusDownloadFailed,
            reason: race,
          );
          expect(stored.localPath, attachment.localPath, reason: race);
        }
      },
    );

    test(
      'P269 explicit deletion-journal race loses companion commit without ID-only fallback or publication',
      () async {
        const groupId = 'group-p269-explicit-companion-journal';
        final groupRepo = InMemoryGroupMessageRepository();
        await groupRepo.saveMessage(
          GroupMessage(
            id: testAttachment.messageId,
            groupId: groupId,
            senderPeerId: 'sender-p269',
            text: '',
            timestamp: DateTime.utc(2026, 7, 22, 20),
            status: 'delivered',
            isIncoming: true,
            createdAt: DateTime.utc(2026, 7, 22, 20),
          ),
        );
        final attachment = _encryptedGroupAttachment(
          testAttachment.copyWith(
            id: 'p269-explicit-companion-journal',
            ownerLane: MediaOwnerLane.group,
            downloadStatus: kMediaDownloadStatusEvicted,
            downloadRetryCount: kMaxDownloadRetries,
          ),
          _jpegBytes,
        );
        final repository = _AtomicOrdinaryGroupFailureMediaRepo()
          ..seedAttachment(attachment);
        repository.beforeExplicitCommit = (_) {
          repository.automaticDeletionJournaled = true;
        };
        final absolutePath = await fileManager.localPathForAttachment(
          contactPeerId: groupId,
          blobId: attachment.id,
          mime: attachment.mime,
        );
        final encryptedCompanion = File('$absolutePath.enc');
        await encryptedCompanion.parent.create(recursive: true);
        final encryptedBytes = _encryptedBytes(_jpegBytes);
        await encryptedCompanion.writeAsBytes(encryptedBytes, flush: true);
        final siblingPath = await fileManager.localPathForAttachment(
          contactPeerId: groupId,
          blobId: 'p269-explicit-companion-sibling',
          mime: attachment.mime,
        );
        final sibling = File(siblingPath);
        await sibling.writeAsBytes(const <int>[10, 11, 12], flush: true);
        final events = <Map<String, dynamic>>[];
        debugSetFlowEventSink(events.add);
        addTearDown(() => debugSetFlowEventSink(null));
        final explicitBridge = _FakeBridge();

        final result = await downloadMedia(
          owner: MediaOwnerLane.group,
          bridge: explicitBridge,
          mediaAttachmentRepo: repository,
          mediaFileManager: fileManager,
          attachment: attachment,
          contactPeerId: groupId,
          groupMessageRepo: groupRepo,
          intent: MediaDownloadIntent.explicitUser,
          enforceGroupMediaPolicy: true,
        );

        expect(result, isNull);
        expect(repository.explicitBeginCalls, 1);
        expect(repository.explicitCommitCalls, 1);
        expect(repository.automaticBeginCalls, 0);
        expect(repository.automaticCommitCalls, 0);
        expect(explicitBridge.commandLog, equals(<String>['blob:decrypt']));
        expect(File(absolutePath).existsSync(), isFalse);
        expect(encryptedCompanion.readAsBytesSync(), encryptedBytes);
        expect(sibling.readAsBytesSync(), const <int>[10, 11, 12]);
        expect(repository.localPathUpdates, isEmpty);
        expect(repository.atomicFailureCalls, isEmpty);
        final stored = (await repository.getAttachmentsForMessage(
          attachment.messageId,
          owner: MediaOwnerLane.group,
        )).single;
        expect(stored.downloadStatus, kMediaDownloadStatusDownloading);
        expect(stored.localPath, isNull);
        final eventNames = events.map((event) => event['event']).toList();
        expect(eventNames, contains('MEDIA_DOWNLOAD_CLAIM_LOST'));
        expect(
          eventNames,
          isNot(
            contains('MEDIA_DOWNLOAD_REPAIRED_FROM_LOCAL_ENCRYPTED_COMPANION'),
          ),
        );
        expect(
          eventNames,
          isNot(contains('MEDIA_DOWNLOAD_DURABLE_LOCAL_PATH_COMMITTED')),
        );
        expect(
          eventNames,
          isNot(contains('MEDIA_GROUP_DURABLE_LOCAL_PATH_DELAYED_PROBE')),
        );
      },
    );

    test(
      'P269 process barrier observes one successful relay attempt after durable group claim and before commit',
      () async {
        const groupId = 'group-p269-process-barrier';
        final groupRepo = InMemoryGroupMessageRepository();
        await groupRepo.saveMessage(
          GroupMessage(
            id: testAttachment.messageId,
            groupId: groupId,
            senderPeerId: 'sender-p269',
            text: '',
            timestamp: DateTime.utc(2026, 7, 22, 14),
            status: 'delivered',
            isIncoming: true,
            createdAt: DateTime.utc(2026, 7, 22, 14),
          ),
        );
        final attachment = _encryptedGroupAttachment(
          testAttachment.copyWith(
            id: 'p269-process-jpeg',
            ownerLane: MediaOwnerLane.group,
          ),
          _jpegBytes,
        );
        final repository = _AtomicOrdinaryGroupFailureMediaRepo()
          ..seedAttachment(attachment);
        final encrypted = _encryptedBytes(_jpegBytes);
        bridge
          ..downloadedBytes = encrypted
          ..downloadResponse = <String, dynamic>{
            'ok': true,
            'id': attachment.id,
            'mime': attachment.mime,
            'size': encrypted.length,
          };
        var barrierCalls = 0;
        var attemptStartedCalls = 0;

        final result = await downloadMedia(
          owner: MediaOwnerLane.group,
          bridge: bridge,
          mediaAttachmentRepo: repository,
          mediaFileManager: fileManager,
          attachment: attachment,
          contactPeerId: groupId,
          groupMessageRepo: groupRepo,
          enforceGroupMediaPolicy: true,
          groupMediaAutomaticDownloadAttemptStarted: (candidate) async {
            attemptStartedCalls++;
            expect(candidate.id, attachment.id);
            expect(
              bridge.commandLog.where((command) => command == 'media:download'),
              isEmpty,
              reason: 'attempt observation precedes local repair and relay',
            );
          },
          groupMediaPostClaimPreCommit: (claimed) async {
            barrierCalls++;
            expect(claimed.id, attachment.id);
            expect(
              bridge.commandLog.where((command) => command == 'media:download'),
              hasLength(1),
              reason: 'barrier is after the first real relay attempt',
            );
            final durable = (await repository.getAttachmentsForMessage(
              attachment.messageId,
              owner: MediaOwnerLane.group,
            )).single;
            expect(durable.downloadStatus, kMediaDownloadStatusDownloading);
            expect(durable.localPath, attachment.localPath);
          },
        );

        expect(attemptStartedCalls, 1);
        expect(barrierCalls, 1);
        expect(result, isNotNull);
        expect(result!.downloadStatus, kMediaDownloadStatusDone);
      },
    );

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
            'errorCode': 'DECRYPT_AUTH_ERROR',
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

  test('TC-365-03a strict group blob ACK follows durable plaintext', () async {
    final fixture = await MediaRepositoryRealDbFixture.create();
    addTearDown(fixture.dispose);
    const groupId = 'tc365-download-group';
    const messageId = 'tc365-download-message';
    const attachmentId = 'tc365-download-attachment';
    const custodyBlobId = 'gmb1_tc365_download_blob';
    const expiresAtMs = 1_930_000_000_000;
    final encrypted = _encryptedBytes(_jpegBytes);
    final contentHash = _hashBytes(encrypted);
    final fingerprint = computeGroupMediaBlobCustodyFingerprint(
      groupId: groupId,
      messageId: messageId,
      attachmentId: attachmentId,
      custodyBlobId: custodyBlobId,
      contentHash: contentHash,
      ciphertextSize: encrypted.length,
      recipientPeerIds: const <String>['device-self', 'device-sibling'],
    );
    final attachment = MediaAttachment(
      id: attachmentId,
      messageId: messageId,
      mime: 'image/jpeg',
      size: _jpegBytes.length,
      mediaType: 'image',
      downloadStatus: kMediaDownloadStatusPending,
      createdAt: '2026-08-14T08:00:00.000Z',
      contentHash: contentHash,
      encryptionKeyBase64: _mediaKey,
      encryptionNonce: _mediaNonce,
      encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
      groupMediaBlobCustodyFingerprint: fingerprint,
      ownerLane: MediaOwnerLane.group,
    );
    final custody = DirectMediaBlobCustodyRow(
      attachmentId: attachmentId,
      messageId: messageId,
      ownerLane: MediaBlobCustodyOwnerLane.group,
      groupId: groupId,
      custodyBlobId: custodyBlobId,
      direction: DirectMediaBlobCustodyDirection.incoming,
      state: DirectMediaBlobCustodyState.incomingCommitted,
      inboxCustodyIncarnationId: null,
      recipientPeerId: null,
      ciphertextRelativePath: null,
      custodyKind: kGroupMediaBlobCustodyKind,
      contentHash: contentHash,
      ciphertextSize: encrypted.length,
      expiresAtMs: expiresAtMs,
      custodyRelayPeerId: null,
      lastAttemptAt: null,
      nextAttemptAt: null,
      createdAt: '2026-08-14T08:00:00.000Z',
      updatedAt: '2026-08-14T08:00:00.000Z',
    );
    await fixture.seedGroupParent(messageId, groupId: groupId);
    await fixture.repo.saveAttachment(attachment, owner: MediaOwnerLane.group);
    await fixture.db.insert(kDirectMediaBlobCustodyTable, custody.toMap());
    final groupMessages = InMemoryGroupMessageRepository();
    await groupMessages.saveMessage(
      GroupMessage(
        id: messageId,
        groupId: groupId,
        senderPeerId: 'sender-tc365',
        text: '',
        timestamp: DateTime.utc(2026, 8, 14, 8),
        status: 'delivered',
        isIncoming: true,
        createdAt: DateTime.utc(2026, 8, 14, 8),
      ),
    );
    final manager = _CanonicalPathFakeMediaFileManager(tempDir.path);
    bridge
      ..downloadedBytes = encrypted
      ..downloadResponse = <String, dynamic>{
        'ok': true,
        'id': custodyBlobId,
        'custodyKind': kGroupMediaBlobCustodyKind,
        'custodyContract': kDirectMediaBlobCustodyContract,
        'contentHash': contentHash,
        'size': encrypted.length,
        'mime': kDirectMediaBlobTransportMime,
        'expiresAtMs': expiresAtMs,
        'custodyRelayPeerId': 'relay-source-tc365',
      }
      ..deleteResponse = <String, dynamic>{'ok': false}
      ..onDeleteRequest = () async {
        final persisted = (await fixture.repo.getAttachmentsForMessage(
          messageId,
          owner: MediaOwnerLane.group,
        )).single;
        expect(persisted.downloadStatus, kMediaDownloadStatusDone);
        expect(persisted.localPath, isNotNull);
        final pending = await (fixture.repo as GroupMediaBlobCustodyRepository)
            .loadGroupMediaBlobCustodyForTarget(
              groupId: groupId,
              attachmentId: attachmentId,
              custodyBlobId: custodyBlobId,
              direction: DirectMediaBlobCustodyDirection.incoming,
            );
        expect(pending, isNotNull);
        expect(pending!.state, DirectMediaBlobCustodyState.incomingAckPending);
        expect(pending.custodyRelayPeerId, 'relay-source-tc365');
        final absolute = await manager.resolveStoredPath(persisted.localPath!);
        expect(await File(absolute).readAsBytes(), _jpegBytes);
      };

    final downloaded = await downloadMedia(
      bridge: bridge,
      mediaAttachmentRepo: fixture.repo,
      mediaFileManager: manager,
      attachment: attachment,
      contactPeerId: groupId,
      owner: MediaOwnerLane.group,
      groupMessageRepo: groupMessages,
      enforceGroupMediaPolicy: true,
      nowMs: () => expiresAtMs - 10000,
    );
    expect(downloaded, isNotNull);
    expect(downloaded!.downloadStatus, kMediaDownloadStatusDone);
    expect(bridge.commandLog, <String>[
      'media:download',
      'blob:decrypt',
      'media:delete',
    ]);
    final retained = await (fixture.repo as GroupMediaBlobCustodyRepository)
        .loadGroupMediaBlobCustodyForTarget(
          groupId: groupId,
          attachmentId: attachmentId,
          custodyBlobId: custodyBlobId,
          direction: DirectMediaBlobCustodyDirection.incoming,
        );
    expect(retained, isNotNull);
    expect(retained!.state, DirectMediaBlobCustodyState.incomingAckPending);
    expect(retained.retryCount, 1);
    expect(retained.custodyRelayPeerId, 'relay-source-tc365');

    // A fresh lifecycle owner sees no pending attachment (plaintext is
    // already DONE); it drains the independent ACK lane and uses only the
    // source relay persisted by the atomic local commit.
    bridge.deleteResponse = <String, dynamic>{
      'ok': true,
      'id': custodyBlobId,
      'ackStatus': 'already_acked',
      'custodyKind': kGroupMediaBlobCustodyKind,
      'custodyContract': kDirectMediaBlobCustodyContract,
      'contentHash': contentHash,
      'size': encrypted.length,
      'mime': kDirectMediaBlobTransportMime,
      'expiresAtMs': expiresAtMs,
      'custodyRelayPeerId': 'relay-source-tc365',
    };
    expect(
      await StrictGroupMediaBlobDownloadAckOwner(
        bridge: bridge,
        mediaAttachmentRepository: fixture.repo,
        mediaFileManager: manager,
        now: () => DateTime.fromMillisecondsSinceEpoch(
          expiresAtMs - 7000,
          isUtc: true,
        ),
      ).retryPendingAcknowledgements(),
      1,
    );
    expect(
      bridge.deleteRequests.last['payload'],
      containsPair('custodyRelayPeerId', 'relay-source-tc365'),
    );
    expect(
      await (fixture.repo as GroupMediaBlobCustodyRepository)
          .loadGroupMediaBlobCustodyForTarget(
            groupId: groupId,
            attachmentId: attachmentId,
            custodyBlobId: custodyBlobId,
            direction: DirectMediaBlobCustodyDirection.incoming,
          ),
      isNull,
    );

    // The local fingerprint survives row retirement. Even a stale caller
    // that drops it cannot demote this attachment to legacy group download.
    final callsBeforeDemotionProbe = bridge.commandLog.length;
    expect(
      await downloadMedia(
        bridge: bridge,
        mediaAttachmentRepo: fixture.repo,
        mediaFileManager: manager,
        attachment: attachment.copyWith(
          clearGroupMediaBlobCustodyFingerprint: true,
          clearLocalPath: true,
          downloadStatus: kMediaDownloadStatusPending,
        ),
        contactPeerId: groupId,
        owner: MediaOwnerLane.group,
        groupMessageRepo: groupMessages,
        enforceGroupMediaPolicy: true,
        nowMs: () => expiresAtMs - 999,
      ),
      isNull,
    );
    expect(bridge.commandLog, hasLength(callsBeforeDemotionProbe));
  });

  group('Plan 347 strict ordinary direct media download', () {
    Future<
      (
        MediaAttachment,
        DirectMediaBlobCustodyRow,
        _CanonicalPathFakeMediaFileManager,
      )
    >
    stageIncoming({
      required MediaRepositoryRealDbFixture fixture,
      required String suffix,
      required List<int> plaintext,
      required int expiresAtMs,
    }) async {
      final messageId = 'tc347-download-message-$suffix';
      final attachmentId = 'tc347-download-blob-$suffix';
      const contactPeerId = 'tc347-download-sender';
      final encrypted = _encryptedBytes(plaintext);
      final contentHash = _hashBytes(encrypted);
      final commitment = DirectMediaBlobCustodyCommitment(
        contentHash: contentHash,
        ciphertextSize: encrypted.length,
        expiresAtMs: expiresAtMs,
      );
      final attachment = MediaAttachment(
        id: attachmentId,
        messageId: messageId,
        mime: 'image/jpeg',
        size: plaintext.length,
        mediaType: 'image',
        downloadStatus: kMediaDownloadStatusPending,
        createdAt: '2026-08-08T11:00:00.000Z',
        contentHash: contentHash,
        encryptionKeyBase64: _mediaKey,
        encryptionNonce: _mediaNonce,
        encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
        blobCustody: commitment,
        ownerLane: MediaOwnerLane.direct,
      );
      final custody = DirectMediaBlobCustodyRow(
        attachmentId: attachmentId,
        messageId: messageId,
        direction: DirectMediaBlobCustodyDirection.incoming,
        state: DirectMediaBlobCustodyState.incomingCommitted,
        inboxCustodyIncarnationId: null,
        recipientPeerId: null,
        ciphertextRelativePath: null,
        contentHash: contentHash,
        ciphertextSize: encrypted.length,
        expiresAtMs: expiresAtMs,
        custodyRelayPeerId: null,
        lastAttemptAt: null,
        nextAttemptAt: null,
        createdAt: '2026-08-08T11:00:00.000Z',
        updatedAt: '2026-08-08T11:00:00.000Z',
      );
      final message = ConversationMessage(
        id: messageId,
        contactPeerId: contactPeerId,
        senderPeerId: contactPeerId,
        text: '',
        timestamp: '2026-08-08T11:00:00.000Z',
        status: 'delivered',
        isIncoming: true,
        createdAt: '2026-08-08T11:00:00.000Z',
      );
      final stage =
          await (fixture.repo as IncomingDirectMediaBlobCustodyRepository)
              .stageIncomingDirectMediaBlobCustody(
                message: message,
                attachments: <MediaAttachment>[attachment],
                custodyRows: <DirectMediaBlobCustodyRow>[custody],
              );
      expect(stage.outcome.name, 'applied');
      return (
        attachment,
        custody,
        _CanonicalPathFakeMediaFileManager(tempDir.path),
      );
    }

    test('TC-347-06b strict download commits before same-source ACK', () async {
      final diagnostics = await AppDiagnostics.installForTesting();
      addTearDown(diagnostics.dispose);
      final fixture = await MediaRepositoryRealDbFixture.create();
      addTearDown(fixture.dispose);
      const expiresAtMs = 1_900_001_000_000;
      final (attachment, custody, manager) = await stageIncoming(
        fixture: fixture,
        suffix: 'relay',
        plaintext: _jpegBytes,
        expiresAtMs: expiresAtMs,
      );
      final encrypted = _encryptedBytes(_jpegBytes);
      bridge.downloadedBytes = encrypted;
      bridge.downloadResponse = <String, dynamic>{
        'ok': true,
        'id': attachment.id,
        'custodyKind': kDirectMediaBlobCustodyKind,
        'custodyContract': kDirectMediaBlobCustodyContract,
        'contentHash': custody.contentHash,
        'size': encrypted.length,
        'mime': kDirectMediaBlobTransportMime,
        'expiresAtMs': expiresAtMs,
        'custodyRelayPeerId': 'relay-source-tc347',
      };
      bridge.deleteResponse = <String, dynamic>{
        'ok': true,
        'id': attachment.id,
        'ackStatus': 'acked',
        'custodyKind': kDirectMediaBlobCustodyKind,
        'custodyContract': kDirectMediaBlobCustodyContract,
        'contentHash': custody.contentHash,
        'size': encrypted.length,
        'mime': kDirectMediaBlobTransportMime,
        'expiresAtMs': expiresAtMs,
        'custodyRelayPeerId': 'relay-source-tc347',
      };
      bridge.onDeleteRequest = () async {
        final attachmentRows = await fixture.db.query(
          'media_attachments',
          where: 'id = ?',
          whereArgs: <Object?>[attachment.id],
        );
        expect(attachmentRows, hasLength(1));
        expect(
          attachmentRows.single['download_status'],
          kMediaDownloadStatusDone,
        );
        expect(attachmentRows.single['local_path'], isNotNull);
        final pending = await (fixture.repo as DirectMediaBlobCustodyRepository)
            .loadIncomingDirectMediaBlobCustodyForAttachment(attachment.id);
        expect(
          pending!.state,
          DirectMediaBlobCustodyState.incomingAckPending,
          reason: 'the source-pinned obligation must commit before ACK',
        );
        expect(pending.custodyRelayPeerId, 'relay-source-tc347');
        final absolutePath = await manager.localPathForAttachment(
          contactPeerId: 'tc347-download-sender',
          blobId: attachment.id,
          mime: attachment.mime,
        );
        expect(File(absolutePath).readAsBytesSync(), _jpegBytes);
      };

      final downloadEntered = Completer<void>();
      final releaseDownload = Completer<void>();
      bridge.beforeDownloadResponse = (_) async {
        downloadEntered.complete();
        await releaseDownload.future;
      };
      final pendingDownload = downloadMedia(
        bridge: bridge,
        mediaAttachmentRepo: fixture.repo,
        mediaFileManager: manager,
        attachment: attachment,
        contactPeerId: 'tc347-download-sender',
        owner: MediaOwnerLane.direct,
        messageRepo: fixture.messageRepo,
        nowMs: () => 1_800_000_000_000,
      );
      await downloadEntered.future;
      expect(
        await downloadMedia(
          bridge: bridge,
          mediaAttachmentRepo: fixture.repo,
          mediaFileManager: manager,
          attachment: attachment.copyWith(
            messageId: 'crossed-parent-without-authority',
          ),
          contactPeerId: 'tc347-download-sender',
          owner: MediaOwnerLane.direct,
          messageRepo: fixture.messageRepo,
          nowMs: () => 1_800_000_000_000,
        ),
        isNull,
      );
      releaseDownload.complete();
      final downloaded = await pendingDownload;
      expect(downloaded, isNotNull);
      expect(downloaded!.downloadStatus, kMediaDownloadStatusDone);
      expect(bridge.commandLog, <String>[
        'media:download',
        'blob:decrypt',
        'media:delete',
      ]);
      expect(bridge.deleteRequests, hasLength(1));
      expect(
        await (fixture.repo as DirectMediaBlobCustodyRepository)
            .loadIncomingDirectMediaBlobCustodyForAttachment(attachment.id),
        isNull,
        reason: 'only the exact successful same-source ACK retires v111',
      );
      final events = (await diagnostics.eventsForTesting())
          .where((e) => e['feature'] == 'media')
          .toList();
      final milestones = events
          .where((e) => e['outcome'] == 'ok')
          .map((e) => e['stage'])
          .toList();
      expect(
        milestones,
        containsAllInOrder([
          'download',
          'verify',
          'decrypt',
          'verify',
          'commit',
          'receipt',
        ]),
      );
      expect(events.last['stage'], 'finish');
      expect(events.last['outcome'], 'success');
      final terminals = events.where((e) => e['stage'] == 'finish').toList();
      expect(terminals.map((e) => e['outcome']).toSet(), {'failed', 'success'});
      expect(
        terminals.map((e) => e['attemptId']).toSet(),
        hasLength(2),
        reason:
            'a simultaneous authority refusal must not close the valid transfer attempt',
      );
      expect(events.map((e) => e['traceId']).toSet(), hasLength(1));
      expect(jsonEncode(events), isNot(contains(attachment.id)));
      expect(jsonEncode(events), isNot(contains(custody.contentHash)));
    });

    test(
      'TC-347-06d verified LAN adoption suppresses strict ACK until expiry',
      () async {
        final fixture = await MediaRepositoryRealDbFixture.create();
        addTearDown(fixture.dispose);
        const expiresAtMs = 1_900_002_000_000;
        final (attachment, custody, manager) = await stageIncoming(
          fixture: fixture,
          suffix: 'lan',
          plaintext: _jpegBytes,
          expiresAtMs: expiresAtMs,
        );
        final absolutePath = await manager.localPathForAttachment(
          contactPeerId: 'tc347-download-sender',
          blobId: attachment.id,
          mime: attachment.mime,
        );
        final lanCiphertext = File('$absolutePath.enc');
        await lanCiphertext.parent.create(recursive: true);
        await lanCiphertext.writeAsBytes(
          _encryptedBytes(_jpegBytes),
          flush: true,
        );

        final adopted = await downloadMedia(
          bridge: bridge,
          mediaAttachmentRepo: fixture.repo,
          mediaFileManager: manager,
          attachment: attachment,
          contactPeerId: 'tc347-download-sender',
          owner: MediaOwnerLane.direct,
          messageRepo: fixture.messageRepo,
          nowMs: () => expiresAtMs - 1,
        );
        expect(adopted, isNotNull);
        expect(adopted!.downloadStatus, kMediaDownloadStatusDone);
        expect(File(absolutePath).readAsBytesSync(), _jpegBytes);
        expect(bridge.commandLog, <String>['blob:decrypt']);
        expect(bridge.deleteRequests, isEmpty);
        final retained =
            await (fixture.repo as DirectMediaBlobCustodyRepository)
                .loadIncomingDirectMediaBlobCustodyForAttachment(attachment.id);
        expect(retained, isNotNull);
        expect(retained!.state, DirectMediaBlobCustodyState.incomingCommitted);
        expect(retained.custodyRelayPeerId, isNull);
        final incoming =
            fixture.repo as IncomingDirectMediaBlobCustodyRepository;
        expect(
          await incoming.deleteIncomingDirectMediaBlobIfExpired(
            expected: retained,
            nowMs: expiresAtMs - 1,
          ),
          isFalse,
        );
        expect(
          await incoming.deleteIncomingDirectMediaBlobIfExpired(
            expected: retained,
            nowMs: expiresAtMs,
          ),
          isTrue,
        );
        expect(bridge.deleteRequests, isEmpty);
      },
    );

    test(
      'TC-347-06j strict owners share one flight and observe durable ACK authority before ACK',
      () async {
        final fixture = await MediaRepositoryRealDbFixture.create();
        addTearDown(fixture.dispose);
        const expiresAtMs = 1_900_002_100_000;
        final (attachment, custody, manager) = await stageIncoming(
          fixture: fixture,
          suffix: 'shared-owner',
          plaintext: _jpegBytes,
          expiresAtMs: expiresAtMs,
        );
        final encrypted = _encryptedBytes(_jpegBytes);
        final enteredDownload = Completer<void>();
        final releaseDownload = Completer<void>();
        bridge
          ..downloadedBytes = encrypted
          ..downloadResponse = <String, dynamic>{
            'ok': true,
            'id': attachment.id,
            'custodyKind': kDirectMediaBlobCustodyKind,
            'custodyContract': kDirectMediaBlobCustodyContract,
            'contentHash': custody.contentHash,
            'size': encrypted.length,
            'mime': kDirectMediaBlobTransportMime,
            'expiresAtMs': expiresAtMs,
            'custodyRelayPeerId': 'relay-shared-owner',
          }
          ..deleteResponse = <String, dynamic>{
            'ok': true,
            'id': attachment.id,
            'ackStatus': 'acked',
            'custodyKind': kDirectMediaBlobCustodyKind,
            'custodyContract': kDirectMediaBlobCustodyContract,
            'contentHash': custody.contentHash,
            'size': encrypted.length,
            'mime': kDirectMediaBlobTransportMime,
            'expiresAtMs': expiresAtMs,
            'custodyRelayPeerId': 'relay-shared-owner',
          }
          ..beforeDownloadResponse = (_) async {
            if (!enteredDownload.isCompleted) enteredDownload.complete();
            await releaseDownload.future;
          };

        final observations = <String>[];
        final firstOwner = StrictDirectMediaBlobDownloadAckOwner(
          bridge: bridge,
          mediaAttachmentRepository: fixture.repo,
          mediaFileManager: manager,
          now: () => DateTime.fromMillisecondsSinceEpoch(
            expiresAtMs - 1000,
            isUtc: true,
          ),
          beforeSourcePinnedAck: (row) async {
            observations.add('durable-ack-pending');
            expect(row.state, DirectMediaBlobCustodyState.incomingAckPending);
            final reloaded =
                await (fixture.repo as DirectMediaBlobCustodyRepository)
                    .loadIncomingDirectMediaBlobCustodyForAttachment(
                      attachment.id,
                    );
            expect(reloaded, isNotNull);
            expect(reloaded!.exactDatabaseProjectionMatches(row), isTrue);
          },
        );
        final secondOwner = StrictDirectMediaBlobDownloadAckOwner(
          bridge: bridge,
          mediaAttachmentRepository: fixture.repo,
          mediaFileManager: manager,
          now: () => DateTime.fromMillisecondsSinceEpoch(
            expiresAtMs - 1000,
            isUtc: true,
          ),
          beforeSourcePinnedAck: (_) {
            observations.add('unexpected-second-owner-callback');
          },
        );
        bridge.onDeleteRequest = () {
          observations.add('source-pinned-ack');
        };

        final first = firstOwner.downloadAndAcknowledge(
          attachment: attachment,
          contactPeerId: 'tc347-download-sender',
        );
        await enteredDownload.future;
        final second = secondOwner.downloadAndAcknowledge(
          attachment: attachment,
          contactPeerId: 'tc347-download-sender',
        );
        expect(identical(first, second), isTrue);
        expect(
          bridge.commandLog.where((command) => command == 'media:download'),
          hasLength(1),
        );
        releaseDownload.complete();

        final results = await Future.wait(<Future<MediaAttachment?>>[
          first,
          second,
        ]);
        expect(results, everyElement(isNotNull));
        expect(
          bridge.commandLog.where((command) => command == 'media:download'),
          hasLength(1),
        );
        expect(
          bridge.commandLog.where((command) => command == 'media:delete'),
          hasLength(1),
        );
        expect(observations, <String>[
          'durable-ack-pending',
          'source-pinned-ack',
        ]);
      },
    );

    test(
      'TC-347-06k strict download rejects whitespace-padded source relay exactly',
      () async {
        final fixture = await MediaRepositoryRealDbFixture.create();
        addTearDown(fixture.dispose);
        const expiresAtMs = 1_900_002_200_000;
        final (attachment, custody, manager) = await stageIncoming(
          fixture: fixture,
          suffix: 'padded-source',
          plaintext: _jpegBytes,
          expiresAtMs: expiresAtMs,
        );
        final encrypted = _encryptedBytes(_jpegBytes);
        bridge.downloadedBytes = encrypted;

        for (final paddedSource in const <String>[
          ' relay-padded-source',
          'relay-padded-source ',
        ]) {
          bridge.downloadResponse = <String, dynamic>{
            'ok': true,
            'id': attachment.id,
            'custodyKind': kDirectMediaBlobCustodyKind,
            'custodyContract': kDirectMediaBlobCustodyContract,
            'contentHash': custody.contentHash,
            'size': encrypted.length,
            'mime': kDirectMediaBlobTransportMime,
            'expiresAtMs': expiresAtMs,
            'custodyRelayPeerId': paddedSource,
          };
          expect(
            await downloadMedia(
              bridge: bridge,
              mediaAttachmentRepo: fixture.repo,
              mediaFileManager: manager,
              attachment: attachment,
              contactPeerId: 'tc347-download-sender',
              owner: MediaOwnerLane.direct,
              messageRepo: fixture.messageRepo,
              nowMs: () => expiresAtMs - 1000,
            ),
            isNull,
          );
        }

        expect(bridge.commandLog, <String>['media:download', 'media:download']);
        final retained =
            await (fixture.repo as DirectMediaBlobCustodyRepository)
                .loadIncomingDirectMediaBlobCustodyForAttachment(attachment.id);
        expect(retained, isNotNull);
        expect(retained!.state, DirectMediaBlobCustodyState.incomingCommitted);
      },
    );

    test(
      'TC-347-06l strict expiry atomically terminalizes and blocks legacy after restart',
      () async {
        var fixture = await MediaRepositoryRealDbFixture.create(
          databasePath: '${tempDir.path}/tc347-strict-expiry.db',
        );
        try {
          const expiresAtMs = 1_900_002_300_000;
          final (attachment, custody, manager) = await stageIncoming(
            fixture: fixture,
            suffix: 'expiry-restart',
            plaintext: _jpegBytes,
            expiresAtMs: expiresAtMs,
          );
          final expectedFingerprint =
              computeDirectMediaBlobCommitmentFingerprint(
                attachmentId: attachment.id,
                commitment: attachment.blobCustody!,
              );
          expect(
            await (fixture.repo as IncomingDirectMediaBlobCustodyRepository)
                .deleteIncomingDirectMediaBlobIfExpired(
                  expected: custody,
                  nowMs: expiresAtMs,
                ),
            isTrue,
          );
          final terminalRow = await fixture.rawAttachmentRow(attachment.id);
          expect(terminalRow, isNotNull);
          expect(
            terminalRow!['download_status'],
            kMediaDownloadStatusDownloadFailed,
          );
          expect(
            terminalRow['direct_media_blob_custody_fingerprint'],
            expectedFingerprint,
          );
          expect(
            await (fixture.repo as DirectMediaBlobCustodyRepository)
                .loadIncomingDirectMediaBlobCustodyForAttachment(attachment.id),
            isNull,
          );

          fixture = await fixture.reopen();
          final afterRestart = (await fixture.repo.getAttachmentsForMessage(
            attachment.messageId,
            owner: MediaOwnerLane.direct,
          )).single;
          expect(
            afterRestart.downloadStatus,
            kMediaDownloadStatusDownloadFailed,
          );
          expect(
            afterRestart.directMediaBlobCustodyFingerprint,
            expectedFingerprint,
          );

          final staleProoflessUiCopy = afterRestart.copyWith(
            clearDirectMediaBlobCustodyFingerprint: true,
          );
          expect(
            await downloadMedia(
              bridge: bridge,
              mediaAttachmentRepo: fixture.repo,
              mediaFileManager: manager,
              attachment: staleProoflessUiCopy,
              contactPeerId: 'tc347-download-sender',
              owner: MediaOwnerLane.direct,
              messageRepo: fixture.messageRepo,
              nowMs: () => expiresAtMs + 1,
            ),
            isNull,
          );
          expect(bridge.commandLog, isEmpty);
        } finally {
          await fixture.dispose();
        }
      },
    );

    test(
      'TC-351-05 delete during strict download cannot resurrect canonical media',
      () async {
        final fixture = await MediaRepositoryRealDbFixture.create();
        addTearDown(fixture.dispose);
        const expiresAtMs = 1_900_002_400_000;
        final (attachment, custody, manager) = await stageIncoming(
          fixture: fixture,
          suffix: 'delete-race',
          plaintext: _jpegBytes,
          expiresAtMs: expiresAtMs,
        );
        final encrypted = _encryptedBytes(_jpegBytes);
        bridge.downloadedBytes = encrypted;
        bridge.downloadResponse = <String, dynamic>{
          'ok': true,
          'id': attachment.id,
          'custodyKind': kDirectMediaBlobCustodyKind,
          'custodyContract': kDirectMediaBlobCustodyContract,
          'contentHash': custody.contentHash,
          'size': encrypted.length,
          'mime': kDirectMediaBlobTransportMime,
          'expiresAtMs': expiresAtMs,
          'custodyRelayPeerId': 'relay-source-tc351',
        };

        // The author's deletion wins in flight — after this owner passed every
        // pre-transfer check and before its own local-path commit. The startup
        // `incoming_committed` retry lane enters here with no eligibility
        // precheck of its own, so the DB commit is the only guard left.
        bridge.beforeDownloadResponse = (_) async {
          await fixture.db.update(
            'messages',
            <String, Object?>{
              'text': '',
              'deleted_at': '2026-08-09T09:00:00.000Z',
              'deleted_by_peer_id': 'tc347-download-sender',
            },
            where: 'id = ?',
            whereArgs: <Object?>[attachment.messageId],
          );
        };

        final downloaded =
            await StrictDirectMediaBlobDownloadAckOwner(
              bridge: bridge,
              mediaAttachmentRepository: fixture.repo,
              mediaFileManager: manager,
              now: () => DateTime.fromMillisecondsSinceEpoch(
                1_800_000_000_000,
                isUtc: true,
              ),
            ).downloadAndAcknowledge(
              attachment: attachment,
              contactPeerId: 'tc347-download-sender',
            );
        expect(downloaded, isNull);

        final absolutePath = await manager.localPathForAttachment(
          contactPeerId: 'tc347-download-sender',
          blobId: attachment.id,
          mime: attachment.mime,
        );
        expect(
          File(absolutePath).existsSync(),
          isFalse,
          reason: 'a losing promotion must remove its own canonical plaintext',
        );
        final row = await fixture.rawAttachmentRow(attachment.id);
        expect(row!['local_path'], isNull);
        expect(row['download_status'], kMediaDownloadStatusPending);
        expect(bridge.deleteRequests, isEmpty);

        // v111 remains the independent obligation: the deletion is not a blob
        // ACK and must not retire or rewrite the incoming custody row.
        final retained =
            await (fixture.repo as DirectMediaBlobCustodyRepository)
                .loadIncomingDirectMediaBlobCustodyForAttachment(attachment.id);
        expect(retained, isNotNull);
        expect(retained!.state, DirectMediaBlobCustodyState.incomingCommitted);
        expect(
          await (fixture.repo as IncomingDirectMediaBlobCustodyRepository)
              .deleteIncomingDirectMediaBlobIfExpired(
                expected: retained,
                nowMs: expiresAtMs,
              ),
          isTrue,
          reason: 'expiry must still converge from v111 alone after deletion',
        );
      },
    );
  });

  group('229 download/eviction CAS', () {
    Future<void> seedProtectedParent(
      MediaRepositoryRealDbFixture fixture,
      String messageId, {
      String contactId = 'contact-private',
    }) async {
      await fixture.seedDirectParent(messageId, contactPeerId: contactId);
      await fixture.db.update(
        'messages',
        {
          'private_media_policy_version': 1,
          'private_media_mode': 'protected',
          'private_media_state': 'available',
          'private_media_received_at_ms': 1000,
          'private_media_clock_high_water_ms': 1000,
        },
        where: 'id = ?',
        whereArgs: [messageId],
      );
    }

    test(
      'private decrypt failures retry only operational errors and preserve protection',
      () async {
        final diagnostics = await AppDiagnostics.installForTesting();
        addTearDown(diagnostics.dispose);
        for (final mode in ['protected', 'view_once']) {
          for (final code in [
            'DECRYPT_IO_ERROR',
            'DECRYPT_ERROR',
            'DECRYPT_AUTH_ERROR',
            'DECRYPT_METADATA_ERROR',
          ]) {
            final retryable =
                code == 'DECRYPT_IO_ERROR' || code == 'DECRYPT_ERROR';
            final fixture = await MediaRepositoryRealDbFixture.create();
            try {
              final messageId = 'decrypt-recovery-$mode-$code';
              final attachmentId = '$messageId-photo';
              await seedProtectedParent(fixture, messageId);
              await fixture.db.update(
                'messages',
                {'private_media_mode': mode},
                where: 'id = ?',
                whereArgs: [messageId],
              );
              final attachment = _encryptedGroupAttachment(
                MediaAttachment(
                  id: attachmentId,
                  messageId: messageId,
                  mime: 'image/jpeg',
                  size: _jpegBytes.length,
                  mediaType: 'image',
                  downloadStatus: kMediaDownloadStatusPending,
                  createdAt: '2026-09-08T18:06:00.000Z',
                ),
                _jpegBytes,
              );
              await fixture.repo.saveAttachment(
                attachment,
                owner: MediaOwnerLane.direct,
              );
              final encrypted = _encryptedBytes(_jpegBytes);
              final localBridge = _FakeBridge()
                ..downloadedBytes = encrypted
                ..downloadResponse = {
                  'ok': true,
                  'id': attachmentId,
                  'mime': 'application/octet-stream',
                  'size': encrypted.length,
                }
                ..decryptResponse = {
                  'ok': false,
                  'errorCode': code,
                  'errorMessage': 'write decrypted file: permission denied',
                };
              final deleted = Completer<void>();
              localBridge.onDeleteRequest = () => deleted.complete();
              final manager = _CanonicalPathFakeMediaFileManager(tempDir.path);
              Future<MediaAttachment?> attempt(MediaAttachment current) =>
                  downloadMedia(
                    bridge: localBridge,
                    mediaAttachmentRepo: fixture.repo,
                    mediaFileManager: manager,
                    attachment: current,
                    contactPeerId: 'contact-private',
                    owner: MediaOwnerLane.direct,
                    messageRepo: fixture.messageRepo,
                    intent: MediaDownloadIntent.explicitUser,
                    nowMs: () => 1200,
                  );

              expect(await attempt(attachment), isNull);
              final trace = diagnostics.traceForOperation(
                'media:$attachmentId',
              );
              var diagnosticEvents = (await diagnostics.eventsForTesting())
                  .where((e) => e['traceId'] == trace)
                  .toList();
              final reason = switch (code) {
                'DECRYPT_IO_ERROR' => 'io_failed',
                'DECRYPT_AUTH_ERROR' => 'auth_failed',
                'DECRYPT_METADATA_ERROR' => 'metadata_invalid',
                _ => 'unknown',
              };
              expect(
                diagnosticEvents,
                contains(
                  predicate<Map<String, Object?>>(
                    (e) =>
                        e['stage'] == 'decrypt' &&
                        e['outcome'] == 'failed' &&
                        e['reason'] == reason,
                  ),
                ),
              );
              expect(
                diagnosticEvents.where((e) => e['stage'] == 'receipt'),
                isEmpty,
              );
              final failedAttempt = diagnosticEvents.last['attemptId'];

              final failed = (await fixture.repo.getAttachmentsForMessage(
                messageId,
                owner: MediaOwnerLane.direct,
              )).single;
              expect(
                failed.downloadStatus,
                retryable
                    ? kMediaDownloadStatusFailed
                    : kMediaDownloadStatusIntegrityFailed,
              );
              expect(failed.downloadRetryCount ?? 0, retryable ? 1 : 0);
              expect(failed.localPath, isNull);
              expect(localBridge.deleteRequests, isEmpty);
              expect(
                (await fixture.messageRepo.getMessage(
                  messageId,
                ))!.privateMediaState,
                PrivateMediaLifecycleState.available,
              );
              final canonical = await manager.localPathForAttachment(
                contactPeerId: 'contact-private',
                blobId: attachmentId,
                mime: attachment.mime,
              );
              expect(File(canonical).existsSync(), isFalse);
              expect(File('$canonical.enc.dec').existsSync(), isFalse);

              localBridge.decryptResponse = null;
              if (!retryable) {
                final callsBeforeRetry = localBridge.commandLog.length;
                expect(await attempt(failed), isNull);
                expect(localBridge.commandLog, hasLength(callsBeforeRetry));
                expect(localBridge.deleteRequests, isEmpty);
                continue;
              }
              final recovered = await attempt(failed);
              expect(recovered, isNotNull);
              expect(recovered!.downloadStatus, kMediaDownloadStatusDone);
              expect(File(recovered.localPath!).readAsBytesSync(), _jpegBytes);
              await deleted.future.timeout(const Duration(seconds: 1));
              await Future<void>.delayed(Duration.zero);
              expect(localBridge.deleteRequests, hasLength(1));
              diagnosticEvents = (await diagnostics.eventsForTesting())
                  .where((e) => e['traceId'] == trace)
                  .toList();
              final success = diagnosticEvents
                  .where(
                    (e) => e['stage'] == 'finish' && e['outcome'] == 'success',
                  )
                  .single;
              expect(success['attemptId'], isNot(failedAttempt));
              expect(
                diagnosticEvents,
                contains(
                  predicate<Map<String, Object?>>(
                    (e) => e['stage'] == 'commit' && e['outcome'] == 'ok',
                  ),
                ),
              );
              expect(
                diagnosticEvents,
                contains(
                  predicate<Map<String, Object?>>(
                    (e) => e['stage'] == 'receipt' && e['outcome'] == 'ok',
                  ),
                ),
              );
              expect(
                jsonEncode(diagnosticEvents),
                isNot(contains(attachmentId)),
              );
              expect(
                jsonEncode(diagnosticEvents),
                isNot(contains('permission denied')),
              );

              expect(
                (await fixture.messageRepo.getMessage(
                  messageId,
                ))!.privateMediaState,
                PrivateMediaLifecycleState.available,
                reason: 'download recovery must not consume a view-once photo',
              );
            } finally {
              await fixture.dispose();
            }
          }
        }
      },
    );

    test(
      'private entry rejects wrong contact before bridge or mutation',
      () async {
        final fixture = await MediaRepositoryRealDbFixture.create();
        addTearDown(fixture.dispose);
        const messageId = 'private-wrong-contact';
        const attachment = MediaAttachment(
          id: 'private-wrong-contact-att',
          messageId: messageId,
          mime: 'image/jpeg',
          size: 3,
          mediaType: 'image',
          downloadStatus: 'pending',
          createdAt: '2026-07-11T00:00:00.000Z',
        );
        await seedProtectedParent(
          fixture,
          messageId,
          contactId: 'contact-authoritative',
        );
        await fixture.repo.saveAttachment(
          attachment,
          owner: MediaOwnerLane.direct,
        );

        expect(
          await downloadMedia(
            bridge: bridge,
            mediaAttachmentRepo: fixture.repo,
            mediaFileManager: _CanonicalPathFakeMediaFileManager(tempDir.path),
            attachment: attachment,
            contactPeerId: 'contact-wrong',
            owner: MediaOwnerLane.direct,
            messageRepo: fixture.messageRepo,
            intent: MediaDownloadIntent.explicitUser,
            nowMs: () => 1100,
          ),
          isNull,
        );
        expect(bridge.commandLog, isEmpty);
        expect(
          (await fixture.rawAttachmentRow(attachment.id))!['download_status'],
          'pending',
        );
      },
    );

    test(
      'private entry rejects traversal and input-only attachment identities',
      () async {
        final fixture = await MediaRepositoryRealDbFixture.create();
        addTearDown(fixture.dispose);
        const messageId = 'private-unsafe-entry';
        await seedProtectedParent(fixture, messageId);
        const traversal = MediaAttachment(
          id: '../outside-private',
          messageId: messageId,
          mime: 'image/jpeg',
          size: 3,
          mediaType: 'image',
          downloadStatus: 'pending',
          createdAt: '2026-07-11T00:00:00.000Z',
        );
        await fixture.repo.saveAttachment(
          traversal,
          owner: MediaOwnerLane.direct,
        );
        final manager = _CanonicalPathFakeMediaFileManager(tempDir.path);

        expect(
          await downloadMedia(
            bridge: bridge,
            mediaAttachmentRepo: fixture.repo,
            mediaFileManager: manager,
            attachment: traversal,
            contactPeerId: 'contact-private',
            owner: MediaOwnerLane.direct,
            messageRepo: fixture.messageRepo,
            intent: MediaDownloadIntent.explicitUser,
          ),
          isNull,
        );
        const inputOnly = MediaAttachment(
          id: 'input-only-private',
          messageId: messageId,
          mime: 'image/jpeg',
          size: 3,
          mediaType: 'image',
          downloadStatus: 'pending',
          createdAt: '2026-07-11T00:00:00.000Z',
        );
        expect(
          await downloadMedia(
            bridge: bridge,
            mediaAttachmentRepo: fixture.repo,
            mediaFileManager: manager,
            attachment: inputOnly,
            contactPeerId: 'contact-private',
            owner: MediaOwnerLane.direct,
            messageRepo: fixture.messageRepo,
            intent: MediaDownloadIntent.explicitUser,
          ),
          isNull,
        );
        expect(bridge.commandLog, isEmpty);
        expect(
          (await fixture.rawAttachmentRow(traversal.id))!['download_status'],
          'pending',
        );
      },
    );

    test(
      'private local-ready rejects zero truncated and symlink files',
      () async {
        final fixture = await MediaRepositoryRealDbFixture.create();
        addTearDown(fixture.dispose);
        const messageId = 'private-local-ready-size';
        const attachmentId = 'private-local-ready-size-att';
        const relativePath =
            'media/contact-private/private-local-ready-size-att.jpg';
        const attachment = MediaAttachment(
          id: attachmentId,
          messageId: messageId,
          mime: 'image/jpeg',
          size: 3,
          mediaType: 'image',
          localPath: relativePath,
          downloadStatus: 'done',
          createdAt: '2026-07-11T00:00:00.000Z',
        );
        await seedProtectedParent(fixture, messageId);
        await fixture.repo.saveAttachment(
          attachment,
          owner: MediaOwnerLane.direct,
        );
        final manager = _CanonicalPathFakeMediaFileManager(tempDir.path);
        final canonical = File('${tempDir.path}/$relativePath')
          ..createSync(recursive: true);

        for (final bytes in const <List<int>>[
          [],
          [1, 2],
        ]) {
          canonical.writeAsBytesSync(bytes);
          expect(
            await downloadMedia(
              bridge: bridge,
              mediaAttachmentRepo: fixture.repo,
              mediaFileManager: manager,
              attachment: attachment,
              contactPeerId: 'contact-private',
              owner: MediaOwnerLane.direct,
              messageRepo: fixture.messageRepo,
              intent: MediaDownloadIntent.explicitUser,
              nowMs: () => 1100,
            ),
            isNull,
          );
        }

        final external = File('${tempDir.path}/external-private.jpg')
          ..writeAsBytesSync(const [1, 2, 3]);
        canonical.deleteSync();
        Link(canonical.path).createSync(external.path);
        expect(
          await downloadMedia(
            bridge: bridge,
            mediaAttachmentRepo: fixture.repo,
            mediaFileManager: manager,
            attachment: attachment,
            contactPeerId: 'contact-private',
            owner: MediaOwnerLane.direct,
            messageRepo: fixture.messageRepo,
            intent: MediaDownloadIntent.explicitUser,
            nowMs: () => 1100,
          ),
          isNull,
        );
        expect(bridge.commandLog, isEmpty);
        expect(external.readAsBytesSync(), const [1, 2, 3]);
        expect(
          (await fixture.rawAttachmentRow(attachmentId))!['download_status'],
          'done',
        );
      },
    );

    test(
      'private download losing to expiry cannot commit or retain promoted bytes',
      () async {
        final fixture = await MediaRepositoryRealDbFixture.create();
        addTearDown(fixture.dispose);
        const contactId = 'contact-private-cas';
        const messageId = 'msg-private-cas';
        const attachmentId = 'blob-private-cas';
        await fixture.seedDirectParent(messageId, contactPeerId: contactId);
        await fixture.db.update(
          'messages',
          {
            'private_media_policy_version': 1,
            'private_media_mode': 'disappearing',
            'private_media_duration_seconds': 3600,
            'private_media_state': 'available',
            'private_media_received_at_ms': 1000,
            'private_media_expires_at_ms': 1500,
            'private_media_clock_high_water_ms': 1000,
          },
          where: 'id = ?',
          whereArgs: [messageId],
        );

        const attachment = MediaAttachment(
          id: attachmentId,
          messageId: messageId,
          mime: 'image/jpeg',
          size: 3,
          mediaType: 'image',
          downloadStatus: 'pending',
          createdAt: '2026-07-10T09:00:00.000Z',
        );
        await fixture.repo.saveAttachment(
          attachment,
          owner: MediaOwnerLane.direct,
        );
        final canonicalFileManager = _CanonicalPathFakeMediaFileManager(
          tempDir.path,
        );
        final canonicalPath =
            '${tempDir.path}/media/$contactId/$attachmentId.jpg';
        final stagedPath = '$canonicalPath.part';
        var clockMs = 1000;
        final engine = PrivateMediaLifecycleEngine(
          adapter: DirectPrivateMediaLifecycle(
            messageRepository: fixture.messageRepo,
            mediaAttachmentRepository: fixture.repo,
            mediaFileManager: canonicalFileManager,
          ),
          lifecycleLock: fixture.repo.lifecycleLock,
          nowMs: () => clockMs,
        );

        bridge.beforeDownloadResponse = (request) async {
          final claimed = await fixture.rawAttachmentRow(attachmentId);
          expect(
            claimed!['download_status'],
            kMediaDownloadStatusDownloading,
            reason:
                'the earlier parent read and attachment claim precede transfer',
          );
          expect(
            await fixture.messageRepo.advancePrivateMediaClock(
              messageId,
              nowMs: 1500,
            ),
            isTrue,
            reason: 'expiry wins while transfer is paused before final commit',
          );
          clockMs = 1500;
          final duringTransfer = await engine.reconcileLocalLifecycle();
          expect(duringTransfer.retainedAfterError, greaterThanOrEqualTo(1));
          expect(await fixture.rawAttachmentRow(attachmentId), isNotNull);
        };

        final result = await downloadMedia(
          bridge: bridge,
          mediaAttachmentRepo: fixture.repo,
          mediaFileManager: canonicalFileManager,
          attachment: attachment,
          contactPeerId: contactId,
          owner: MediaOwnerLane.direct,
          messageRepo: fixture.messageRepo,
          intent: MediaDownloadIntent.explicitUser,
          nowMs: () => clockMs,
        );

        expect(result, isNull);
        final parent = await fixture.messageRepo.getMessage(messageId);
        expect(parent!.privateMediaState, PrivateMediaLifecycleState.expired);
        final afterTransfer = await engine.reconcileLocalLifecycle();
        expect(afterTransfer.cleanupCompleted, greaterThanOrEqualTo(1));
        expect(await fixture.rawAttachmentRow(attachmentId), isNull);
        expect(
          File(canonicalPath).existsSync(),
          isFalse,
          reason: 'the losing late completion removes only its promoted bytes',
        );
        expect(File(stagedPath).existsSync(), isFalse);
      },
    );

    test(
      'private relay failure branches converge without row or path resurrection',
      () async {
        for (final failure in const [
          'forced transient transport failure',
          'Blob not found',
        ]) {
          final fixture = await MediaRepositoryRealDbFixture.create();
          try {
            final suffix = failure.startsWith('Blob')
                ? 'unavailable'
                : 'transient';
            final messageId = 'private-failure-$suffix';
            final attachmentId = 'private-failure-$suffix-att';
            await seedProtectedParent(fixture, messageId);
            final attachment = MediaAttachment(
              id: attachmentId,
              messageId: messageId,
              mime: 'image/jpeg',
              size: 3,
              mediaType: 'image',
              downloadStatus: 'pending',
              createdAt: '2026-07-11T00:00:00.000Z',
            );
            await fixture.repo.saveAttachment(
              attachment,
              owner: MediaOwnerLane.direct,
            );
            final manager = _CanonicalPathFakeMediaFileManager(tempDir.path);
            final localBridge = _FakeBridge()
              ..downloadResponse = {'ok': false, 'errorMessage': failure};
            final engine = PrivateMediaLifecycleEngine(
              adapter: DirectPrivateMediaLifecycle(
                messageRepository: fixture.messageRepo,
                mediaAttachmentRepository: fixture.repo,
                mediaFileManager: manager,
              ),
              lifecycleLock: fixture.repo.lifecycleLock,
              nowMs: () => 1200,
            );
            String? stagedPath;
            localBridge.beforeDownloadResponse = (request) async {
              stagedPath =
                  (request['payload'] as Map<String, dynamic>)['outputPath']
                      as String;
              File(stagedPath!)
                ..createSync(recursive: true)
                ..writeAsBytesSync(const [7, 8]);
              expect(
                await fixture.messageRepo.hidePrivateMediaForMe(
                  messageId,
                  hiddenAt: '2026-07-11T00:00:01.200Z',
                  nowMs: 1200,
                ),
                isTrue,
              );
              expect(
                (await engine.reconcileLocalLifecycle()).retainedAfterError,
                greaterThanOrEqualTo(1),
              );
            };

            expect(
              await downloadMedia(
                bridge: localBridge,
                mediaAttachmentRepo: fixture.repo,
                mediaFileManager: manager,
                attachment: attachment,
                contactPeerId: 'contact-private',
                owner: MediaOwnerLane.direct,
                messageRepo: fixture.messageRepo,
                intent: MediaDownloadIntent.explicitUser,
                nowMs: () => 1200,
              ),
              isNull,
            );
            expect(
              (await engine.reconcileLocalLifecycle()).cleanupCompleted,
              greaterThanOrEqualTo(1),
            );
            expect(await fixture.rawAttachmentRow(attachmentId), isNull);
            expect(File(stagedPath!).existsSync(), isFalse);
            expect(
              File(
                '${tempDir.path}/media/contact-private/$attachmentId.jpg',
              ).existsSync(),
              isFalse,
            );
          } finally {
            await fixture.dispose();
          }
        }
      },
    );

    test(
      'private timeout late-write authority scrubs then releases cleanup',
      () async {
        final fixture = await MediaRepositoryRealDbFixture.create();
        addTearDown(fixture.dispose);
        const messageId = 'private-timeout-cleanup';
        const attachmentId = 'private-timeout-cleanup-att';
        await seedProtectedParent(fixture, messageId);
        const attachment = MediaAttachment(
          id: attachmentId,
          messageId: messageId,
          mime: 'image/jpeg',
          size: 3,
          mediaType: 'image',
          downloadStatus: 'pending',
          createdAt: '2026-07-11T00:00:00.000Z',
        );
        await fixture.repo.saveAttachment(
          attachment,
          owner: MediaOwnerLane.direct,
        );
        final manager = _CanonicalPathFakeMediaFileManager(tempDir.path);
        final timeoutBridge = _TimeoutAfterWriteBridge()
          ..downloadedBytes = const [1, 2, 3];
        final engine = PrivateMediaLifecycleEngine(
          adapter: DirectPrivateMediaLifecycle(
            messageRepository: fixture.messageRepo,
            mediaAttachmentRepository: fixture.repo,
            mediaFileManager: manager,
          ),
          lifecycleLock: fixture.repo.lifecycleLock,
          nowMs: () => 1200,
        );
        String? stagedPath;
        timeoutBridge.beforeDownloadResponse = (request) async {
          stagedPath =
              (request['payload'] as Map<String, dynamic>)['outputPath']
                  as String;
          expect(
            await fixture.messageRepo.hidePrivateMediaForMe(
              messageId,
              hiddenAt: '2026-07-11T00:00:01.200Z',
              nowMs: 1200,
            ),
            isTrue,
          );
          expect(
            (await engine.reconcileLocalLifecycle()).retainedAfterError,
            greaterThanOrEqualTo(1),
          );
        };

        expect(
          await downloadMedia(
            bridge: timeoutBridge,
            mediaAttachmentRepo: fixture.repo,
            mediaFileManager: manager,
            attachment: attachment,
            contactPeerId: 'contact-private',
            owner: MediaOwnerLane.direct,
            messageRepo: fixture.messageRepo,
            intent: MediaDownloadIntent.explicitUser,
            latePrivateTransferScrubDelay: Duration.zero,
            nowMs: () => 1200,
          ),
          isNull,
        );
        for (
          var attempt = 0;
          attempt < 100 &&
              directPrivateMediaTransferRegistry.isActive(attachmentId);
          attempt += 1
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        expect(
          directPrivateMediaTransferRegistry.isActive(attachmentId),
          isFalse,
        );
        expect(
          (await engine.reconcileLocalLifecycle()).cleanupCompleted,
          greaterThanOrEqualTo(1),
        );
        expect(await fixture.rawAttachmentRow(attachmentId), isNull);
        expect(File(stagedPath!).existsSync(), isFalse);
        expect(
          File(
            '${tempDir.path}/media/contact-private/$attachmentId.jpg',
          ).existsSync(),
          isFalse,
        );
      },
    );

    test('download and eviction compare and set prevents local copy '
        'resurrection', () async {
      final fixture = await MediaRepositoryRealDbFixture.create();
      addTearDown(fixture.dispose);
      const contactId = 'contact-cas';
      const groupId = 'group-cas';
      await fixture.seedDirectParent('msg-cas', contactPeerId: contactId);
      await fixture.seedGroupParent('msg-cas', groupId: groupId);

      final canonicalFileManager = _CanonicalPathFakeMediaFileManager(
        tempDir.path,
      );
      final directScope = MediaLibraryScope.direct(contactId);
      final manager = MediaStorageManager(
        repository: fixture.repo,
        documentsDirectoryProvider: () async => tempDir.path,
      );

      const attachment = MediaAttachment(
        id: 'blob-cas-1',
        messageId: 'msg-cas',
        mime: 'image/jpeg',
        size: 3,
        mediaType: 'image',
        downloadStatus: 'pending',
        createdAt: '2026-07-10T09:00:00.000Z',
      );
      await fixture.repo.saveAttachment(
        attachment,
        owner: MediaOwnerLane.direct,
      );
      // Same-parent group collision row with its own committed file.
      const siblingRelative = 'media/$groupId/blob-cas-g.jpg';
      final siblingAbsolute = '${tempDir.path}/$siblingRelative';
      File(siblingAbsolute)
        ..createSync(recursive: true)
        ..writeAsBytesSync(const [9, 9, 9]);
      await fixture.repo.saveAttachment(
        const MediaAttachment(
          id: 'blob-cas-g',
          messageId: 'msg-cas',
          mime: 'image/jpeg',
          size: 3,
          mediaType: 'image',
          downloadStatus: 'done',
          localPath: siblingRelative,
          createdAt: '2026-07-10T09:00:00.000Z',
        ),
        owner: MediaOwnerLane.group,
      );

      const canonicalRelative = 'media/$contactId/blob-cas-1.jpg';
      final canonicalAbsolute = '${tempDir.path}/$canonicalRelative';

      // --- Phase 1: the download wins the `downloading` claim; Clear during
      // the transfer is busy with zero mutation. ---
      MediaClearLocalCopyResult? midTransferClear;
      bridge.beforeDownloadResponse = (request) async {
        final row = await fixture.rawAttachmentRow('blob-cas-1');
        expect(
          row!['download_status'],
          kMediaDownloadStatusDownloading,
          reason: 'the CAS begin claim must precede the transfer',
        );
        midTransferClear = await manager.clearLocalCopy(
          scope: directScope,
          attachmentId: 'blob-cas-1',
          mime: 'image/jpeg',
        );
      };
      final downloaded = await downloadMedia(
        bridge: bridge,
        mediaAttachmentRepo: fixture.repo,
        mediaFileManager: canonicalFileManager,
        attachment: attachment,
        contactPeerId: contactId,
        owner: MediaOwnerLane.direct,
      );
      expect(midTransferClear, MediaClearLocalCopyResult.busy);
      expect(downloaded, isNotNull);
      expect(downloaded!.downloadStatus, kMediaDownloadStatusDone);
      final committed = await fixture.rawAttachmentRow('blob-cas-1');
      expect(committed!['download_status'], kMediaDownloadStatusDone);
      expect(committed['local_path'], canonicalRelative);
      expect(File(canonicalAbsolute).existsSync(), isTrue);

      // --- Phase 2: after completion Clear succeeds. ---
      bridge.beforeDownloadResponse = null;
      expect(
        await manager.clearLocalCopy(
          scope: directScope,
          attachmentId: 'blob-cas-1',
          mime: 'image/jpeg',
        ),
        MediaClearLocalCopyResult.cleared,
      );
      expect(File(canonicalAbsolute).existsSync(), isFalse);
      final evictedRow = await fixture.rawAttachmentRow('blob-cas-1');
      expect(evictedRow!['download_status'], kMediaDownloadStatusEvicted);
      expect(evictedRow['local_path'], isNull);

      // --- Phase 3: an explicit retry claims evicted -> downloading, but a
      // forced lost claim means the late completion cannot restore
      // done/path; it removes ONLY the exact canonical artifact it just
      // promoted, and the collision sibling survives untouched. ---
      bridge.beforeDownloadResponse = (request) async {
        // Simulate the claim being lost mid-transfer (a concurrent local
        // state change) — the row leaves `downloading` underneath the
        // running download.
        await fixture.db.rawUpdate(
          "UPDATE media_attachments SET download_status = ?, "
          'local_path = NULL WHERE id = ?',
          [kMediaDownloadStatusEvicted, 'blob-cas-1'],
        );
      };
      final lateCompletion = await downloadMedia(
        bridge: bridge,
        mediaAttachmentRepo: fixture.repo,
        mediaFileManager: canonicalFileManager,
        attachment: attachment.copyWith(
          downloadStatus: kMediaDownloadStatusEvicted,
        ),
        contactPeerId: contactId,
        owner: MediaOwnerLane.direct,
      );
      expect(
        lateCompletion,
        isNull,
        reason: 'a lost claim must fail closed, never resurrect the copy',
      );
      final afterLate = await fixture.rawAttachmentRow('blob-cas-1');
      expect(afterLate!['download_status'], kMediaDownloadStatusEvicted);
      expect(afterLate['local_path'], isNull);
      expect(
        File(canonicalAbsolute).existsSync(),
        isFalse,
        reason:
            'the late completion removes exactly the artifact it '
            'promoted',
      );
      // The sibling lane row and file are untouched by the whole journey.
      final sibling = await fixture.rawAttachmentRow('blob-cas-g');
      expect(sibling!['download_status'], kMediaDownloadStatusDone);
      expect(sibling['local_path'], siblingRelative);
      expect(File(siblingAbsolute).existsSync(), isTrue);
    });
  });
  group('Plan 354 explicit private strict download', () {
    test('TC-354-05a explicit private strict claim and path guard precede '
        'network and commit precedes ACK', () async {
      final downloadSource = File(
        'lib/features/conversation/application/download_media_use_case.dart',
      ).readAsStringSync();
      final ownerSource = File(
        'lib/features/conversation/application/'
        'strict_direct_media_blob_download_ack_owner.dart',
      ).readAsStringSync();

      // 1. The private strict entry requires explicit user intent and an
      //    incoming committed/ACK-pending obligation. Automatic private
      //    download is never routed here.
      final entry = downloadSource.indexOf(
        'requiresDirectPrivateCommit &&\n      effectiveIntent == MediaDownloadIntent.explicitUser',
      );
      expect(
        entry,
        greaterThan(-1),
        reason: 'automatic private download must stay refused',
      );
      final entryBody = downloadSource.substring(entry, entry + 8200);
      expect(
        entryBody.contains('DirectMediaBlobCustodyState.incomingCommitted'),
        isTrue,
      );
      expect(
        entryBody.contains('DirectMediaBlobCustodyState.incomingAckPending'),
        isTrue,
      );

      // 2. The exact attachment-scoped transfer token AND the DB
      //    `downloading` claim are both acquired, under the lifecycle lock,
      //    and the row is requalified, strictly before the strict owner can
      //    consume it. Plan 355 proves this behaviorally in TC-355-01b.
      final tokenIndex = entryBody.indexOf(
        'directPrivateMediaTransferRegistry.tryBegin',
      );
      final claimIndex = entryBody.indexOf(
        'beginDirectPrivateMediaDownloadWithinLock',
      );
      final requalifyIndex = entryBody.indexOf(
        '_requalifyClaimedPrivateAttachment(',
      );
      final ownerIndex = entryBody.indexOf('attachment: claim.row,');
      expect(tokenIndex, greaterThan(-1));
      expect(claimIndex, greaterThan(tokenIndex));
      expect(requalifyIndex, greaterThan(claimIndex));
      expect(ownerIndex, greaterThan(requalifyIndex));
      // A refused claim releases the token and performs zero network.
      expect(
        entryBody.contains(
          'directPrivateMediaTransferRegistry.end(attachment.id, claimed);',
        ),
        isTrue,
      );
      expect(entryBody.contains('if (claim == null) return null;'), isTrue);
      // The token is always released.
      expect(entryBody.contains('} finally {'), isTrue);

      // 3. The owner path-authorizes the canonical target, the legacy LAN
      //    sibling AND both deterministic staging siblings BEFORE any bridge,
      //    network or decrypt work.
      final guard = ownerSource.indexOf(
        '!await _authorizesPrivateTargets(absolutePath)',
      );
      expect(guard, greaterThan(-1));
      final firstNetwork = ownerSource.indexOf('await callP2PMediaDownload(');
      final firstDecrypt = ownerSource.indexOf('await callBlobDecrypt(');
      expect(guard, lessThan(firstNetwork));
      expect(guard, lessThan(firstDecrypt));
      final guardBody = ownerSource.substring(
        ownerSource.indexOf('Future<bool> _authorizesPrivateTargets('),
        firstNetwork,
      );
      expect(
        guardBody.contains('DirectPrivateMediaPathGuard.authorizeTarget('),
        isTrue,
      );
      expect(guardBody.contains('privateCiphertextStagingPath('), isTrue);
      expect(guardBody.contains('privateDecryptStagingPath('), isTrue);
      expect(
        guardBody.contains('return null;'),
        isTrue,
        reason: 'an unsafe symlink refuses with zero mutation and no network',
      );

      // 4. The staging pair is deterministic, so private cleanup and restart
      //    recovery can enumerate it without a wildcard scan.
      expect(
        StrictDirectMediaBlobDownloadAckOwner.privateCiphertextStagingPath(
          '/docs/media/peer/blob.jpg',
        ),
        '/docs/media/peer/blob.jpg.private.enc',
      );
      expect(
        StrictDirectMediaBlobDownloadAckOwner.privateDecryptStagingPath(
          '/docs/media/peer/blob.jpg',
        ),
        '/docs/media/peer/blob.jpg.private.enc.dec',
      );
      final cleanupSource = File(
        'lib/features/conversation/application/'
        'direct_private_media_lifecycle.dart',
      ).readAsStringSync();
      expect(cleanupSource.contains(".path}.private.enc'"), isTrue);
      expect(cleanupSource.contains(".path}.private.enc.dec'"), isTrue);

      // 5. The durable local-path commit precedes the source-pinned ACK, and
      //    a refused commit scrubs only this attempt's canonical plaintext.
      final commitIndex = ownerSource.indexOf(
        'commitIncomingDirectMediaBlobLocalPath(',
      );
      final ackIndex = ownerSource.indexOf(
        '_acknowledgeReloadedPending(custody);',
      );
      expect(commitIndex, greaterThan(-1));
      expect(
        commitIndex,
        lessThan(ownerSource.lastIndexOf('_acknowledgeReloadedPending(')),
        reason: 'the DB commit always precedes the source-pinned ACK',
      );
      expect(ackIndex, greaterThan(-1));
      expect(
        ownerSource.contains(
          'if (!didCommit) {\n              // The DB refused this promotion',
        ),
        isTrue,
      );
    });
  });

  group('Plan 355 private strict download closure', () {
    const contactPeerId = 'tc355-private-sender';
    const relayPeerId = 'tc355-relay-source';

    /// Stages one durable v1 Protected/View-Once initial with its exact v111
    /// obligation, exactly as the receive path would.
    Future<
      ({
        MediaAttachment attachment,
        DirectMediaBlobCustodyRow custody,
        _CanonicalPathFakeMediaFileManager manager,
        String canonicalAbsolutePath,
        List<int> ciphertext,
      })
    >
    stagePrivateIncoming({
      required MediaRepositoryRealDbFixture fixture,
      required String suffix,
      String mode = 'protected',
      String mime = 'image/jpeg',
      String mediaType = 'image',
      int expiresAtMs = 1_900_005_000_000,
      List<int> plaintext = _jpegBytes,
    }) async {
      final messageId = 'tc355-msg-$suffix';
      final attachmentId = 'tc355-blob-$suffix';
      final encrypted = _encryptedBytes(plaintext);
      final contentHash = _hashBytes(encrypted);
      final commitment = DirectMediaBlobCustodyCommitment(
        contentHash: contentHash,
        ciphertextSize: encrypted.length,
        expiresAtMs: expiresAtMs,
      );
      final attachment = MediaAttachment(
        id: attachmentId,
        messageId: messageId,
        mime: mime,
        size: plaintext.length,
        mediaType: mediaType,
        downloadStatus: kMediaDownloadStatusPending,
        createdAt: '2026-08-10T11:00:00.000Z',
        contentHash: contentHash,
        encryptionKeyBase64: _mediaKey,
        encryptionNonce: _mediaNonce,
        encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
        blobCustody: commitment,
        ownerLane: MediaOwnerLane.direct,
      );
      final custody = DirectMediaBlobCustodyRow(
        attachmentId: attachmentId,
        messageId: messageId,
        direction: DirectMediaBlobCustodyDirection.incoming,
        state: DirectMediaBlobCustodyState.incomingCommitted,
        inboxCustodyIncarnationId: null,
        recipientPeerId: null,
        ciphertextRelativePath: null,
        contentHash: contentHash,
        ciphertextSize: encrypted.length,
        expiresAtMs: expiresAtMs,
        custodyRelayPeerId: null,
        lastAttemptAt: null,
        nextAttemptAt: null,
        createdAt: '2026-08-10T11:00:00.000Z',
        updatedAt: '2026-08-10T11:00:00.000Z',
      );
      final message = ConversationMessage(
        id: messageId,
        contactPeerId: contactPeerId,
        senderPeerId: contactPeerId,
        text: '',
        timestamp: '2026-08-10T11:00:00.000Z',
        status: 'delivered',
        isIncoming: true,
        createdAt: '2026-08-10T11:00:00.000Z',
        privateMediaPolicy: PrivateMediaPolicy.fromJson(<String, Object?>{
          'version': 1,
          'mode': mode,
        }),
        privateMediaState: PrivateMediaLifecycleState.available,
        privateMediaReceivedAtMs: 1_800_000_000_000,
        privateMediaClockHighWaterMs: 1_800_000_000_000,
      );
      final stage =
          await (fixture.repo
                  as IncomingDirectPrivateMediaBlobCustodyRepository)
              .stageIncomingDirectPrivateMediaBlobCustody(
                message: message,
                attachment: attachment,
                custodyRow: custody,
              );
      expect(stage.outcome.name, 'applied', reason: suffix);
      final manager = _CanonicalPathFakeMediaFileManager(tempDir.path);
      return (
        attachment: attachment,
        custody: custody,
        manager: manager,
        canonicalAbsolutePath: await manager.localPathForAttachment(
          contactPeerId: contactPeerId,
          blobId: attachmentId,
          mime: mime,
        ),
        ciphertext: encrypted,
      );
    }

    void wireRelay({
      required MediaAttachment attachment,
      required DirectMediaBlobCustodyRow custody,
      required List<int> ciphertext,
    }) {
      bridge.downloadedBytes = ciphertext;
      bridge.downloadResponse = <String, dynamic>{
        'ok': true,
        'id': attachment.id,
        'custodyKind': kDirectMediaBlobCustodyKind,
        'custodyContract': kDirectMediaBlobCustodyContract,
        'contentHash': custody.contentHash,
        'size': ciphertext.length,
        'mime': kDirectMediaBlobTransportMime,
        'expiresAtMs': custody.expiresAtMs,
        'custodyRelayPeerId': relayPeerId,
      };
      bridge.deleteResponse = <String, dynamic>{
        'ok': true,
        'id': attachment.id,
        'ackStatus': 'acked',
        'custodyKind': kDirectMediaBlobCustodyKind,
        'custodyContract': kDirectMediaBlobCustodyContract,
        'contentHash': custody.contentHash,
        'size': ciphertext.length,
        'mime': kDirectMediaBlobTransportMime,
        'expiresAtMs': custody.expiresAtMs,
        'custodyRelayPeerId': relayPeerId,
      };
    }

    test('TC-355-01b explicit private strict download commits before ACK and '
        'never falls through', () async {
      // --- Relay lane: the reloaded `downloading` projection is what the
      // final commit consumes, and the commit precedes the ACK. ---
      for (final mode in const <String>['protected', 'view_once']) {
        final fixture = await MediaRepositoryRealDbFixture.create();
        addTearDown(fixture.dispose);
        bridge = _FakeBridge();
        final staged = await stagePrivateIncoming(
          fixture: fixture,
          suffix: 'relay-$mode',
          mode: mode,
        );
        wireRelay(
          attachment: staged.attachment,
          custody: staged.custody,
          ciphertext: staged.ciphertext,
        );
        var sawClaimedRowDuringTransfer = false;
        bridge.beforeDownloadResponse = (_) async {
          final row = await fixture.rawAttachmentRow(staged.attachment.id);
          sawClaimedRowDuringTransfer =
              row!['download_status'] == kMediaDownloadStatusDownloading;
        };
        var ackSawDurableCommit = false;
        bridge.onDeleteRequest = () async {
          final row = await fixture.rawAttachmentRow(staged.attachment.id);
          final pending =
              await (fixture.repo as DirectMediaBlobCustodyRepository)
                  .loadIncomingDirectMediaBlobCustodyForAttachment(
                    staged.attachment.id,
                  );
          ackSawDurableCommit =
              row!['download_status'] == kMediaDownloadStatusDone &&
              row['local_path'] != null &&
              pending!.state ==
                  DirectMediaBlobCustodyState.incomingAckPending &&
              pending.custodyRelayPeerId == relayPeerId;
        };

        final downloaded = await downloadMedia(
          bridge: bridge,
          mediaAttachmentRepo: fixture.repo,
          mediaFileManager: staged.manager,
          // The caller's snapshot is the stale PRE-claim UI object.
          attachment: staged.attachment,
          contactPeerId: contactPeerId,
          owner: MediaOwnerLane.direct,
          messageRepo: fixture.messageRepo,
          intent: MediaDownloadIntent.explicitUser,
          nowMs: () => 1_800_000_100_000,
        );

        expect(downloaded, isNotNull, reason: mode);
        expect(downloaded!.downloadStatus, kMediaDownloadStatusDone);
        expect(sawClaimedRowDuringTransfer, isTrue, reason: mode);
        expect(
          ackSawDurableCommit,
          isTrue,
          reason: 'the durable commit must precede the source-pinned ACK',
        );
        expect(bridge.commandLog, <String>[
          'media:download',
          'blob:decrypt',
          'media:delete',
        ]);
        expect(
          File(staged.canonicalAbsolutePath).readAsBytesSync(),
          _jpegBytes,
        );
        expect(
          await (fixture.repo as DirectMediaBlobCustodyRepository)
              .loadIncomingDirectMediaBlobCustodyForAttachment(
                staged.attachment.id,
              ),
          isNull,
          reason: 'only the exact successful same-source ACK retires v111',
        );
      }

      // --- LAN lane: a verified source-less adoption commits `done` and
      // deliberately stays `incoming_committed` with no ACK. ---
      {
        final fixture = await MediaRepositoryRealDbFixture.create();
        addTearDown(fixture.dispose);
        bridge = _FakeBridge();
        final staged = await stagePrivateIncoming(
          fixture: fixture,
          suffix: 'lan',
        );
        final lanSource = File('${staged.canonicalAbsolutePath}.enc');
        await lanSource.parent.create(recursive: true);
        await lanSource.writeAsBytes(staged.ciphertext, flush: true);

        final downloaded = await downloadMedia(
          bridge: bridge,
          mediaAttachmentRepo: fixture.repo,
          mediaFileManager: staged.manager,
          attachment: staged.attachment,
          contactPeerId: contactPeerId,
          owner: MediaOwnerLane.direct,
          messageRepo: fixture.messageRepo,
          intent: MediaDownloadIntent.explicitUser,
          nowMs: () => 1_800_000_100_000,
        );

        expect(downloaded, isNotNull);
        expect(downloaded!.downloadStatus, kMediaDownloadStatusDone);
        expect(bridge.commandLog, <String>['blob:decrypt']);
        expect(bridge.deleteRequests, isEmpty);
        final survivor =
            await (fixture.repo as DirectMediaBlobCustodyRepository)
                .loadIncomingDirectMediaBlobCustodyForAttachment(
                  staged.attachment.id,
                );
        expect(survivor!.state, DirectMediaBlobCustodyState.incomingCommitted);
        expect(survivor.custodyRelayPeerId, isNull);
        expect(
          File(staged.canonicalAbsolutePath).readAsBytesSync(),
          _jpegBytes,
        );
        expect(
          lanSource.existsSync(),
          isFalse,
          reason: 'the LAN source is consumed only after a durable commit',
        );
      }

      // --- ACK-pending WITH exact durable local bytes retries only the
      // source-pinned ACK. ---
      {
        final fixture = await MediaRepositoryRealDbFixture.create();
        addTearDown(fixture.dispose);
        bridge = _FakeBridge();
        final staged = await stagePrivateIncoming(
          fixture: fixture,
          suffix: 'ack-retry',
        );
        wireRelay(
          attachment: staged.attachment,
          custody: staged.custody,
          ciphertext: staged.ciphertext,
        );
        final relative = staged.manager.relativePathForAttachment(
          contactPeerId: contactPeerId,
          blobId: staged.attachment.id,
          mime: staged.attachment.mime,
        );
        final canonical = File(staged.canonicalAbsolutePath);
        await canonical.parent.create(recursive: true);
        await canonical.writeAsBytes(_jpegBytes, flush: true);
        await fixture.db.update(
          'media_attachments',
          <String, Object?>{
            'local_path': relative,
            'download_status': kMediaDownloadStatusDone,
          },
          where: 'id = ?',
          whereArgs: <Object?>[staged.attachment.id],
        );
        expect(
          await (fixture.repo as DirectMediaBlobCustodyRepository)
              .transitionDirectMediaBlobCustodyIfExact(
                expected: staged.custody,
                next: staged.custody.copyWith(
                  state: DirectMediaBlobCustodyState.incomingAckPending,
                  custodyRelayPeerId: relayPeerId,
                ),
              ),
          isTrue,
        );

        final adopted = await downloadMedia(
          bridge: bridge,
          mediaAttachmentRepo: fixture.repo,
          mediaFileManager: staged.manager,
          attachment: staged.attachment.copyWith(
            localPath: relative,
            downloadStatus: kMediaDownloadStatusDone,
          ),
          contactPeerId: contactPeerId,
          owner: MediaOwnerLane.direct,
          messageRepo: fixture.messageRepo,
          intent: MediaDownloadIntent.explicitUser,
          nowMs: () => 1_800_000_100_000,
        );

        expect(adopted, isNotNull);
        expect(bridge.commandLog, <String>['media:delete']);
        expect(
          await (fixture.repo as DirectMediaBlobCustodyRepository)
              .loadIncomingDirectMediaBlobCustodyForAttachment(
                staged.attachment.id,
              ),
          isNull,
        );
      }

      // --- ACK-pending WITHOUT durable local bytes never ACKs, claims,
      // downloads, or deletes v111. ---
      {
        final fixture = await MediaRepositoryRealDbFixture.create();
        addTearDown(fixture.dispose);
        bridge = _FakeBridge();
        final staged = await stagePrivateIncoming(
          fixture: fixture,
          suffix: 'ack-no-local',
        );
        wireRelay(
          attachment: staged.attachment,
          custody: staged.custody,
          ciphertext: staged.ciphertext,
        );
        expect(
          await (fixture.repo as DirectMediaBlobCustodyRepository)
              .transitionDirectMediaBlobCustodyIfExact(
                expected: staged.custody,
                next: staged.custody.copyWith(
                  state: DirectMediaBlobCustodyState.incomingAckPending,
                  custodyRelayPeerId: relayPeerId,
                ),
              ),
          isTrue,
        );

        expect(
          await downloadMedia(
            bridge: bridge,
            mediaAttachmentRepo: fixture.repo,
            mediaFileManager: staged.manager,
            attachment: staged.attachment,
            contactPeerId: contactPeerId,
            owner: MediaOwnerLane.direct,
            messageRepo: fixture.messageRepo,
            intent: MediaDownloadIntent.explicitUser,
            nowMs: () => 1_800_000_100_000,
          ),
          isNull,
        );
        expect(bridge.commandLog, isEmpty);
        expect(
          (await fixture.rawAttachmentRow(
            staged.attachment.id,
          ))!['download_status'],
          kMediaDownloadStatusPending,
        );
        final retained =
            await (fixture.repo as DirectMediaBlobCustodyRepository)
                .loadIncomingDirectMediaBlobCustodyForAttachment(
                  staged.attachment.id,
                );
        expect(retained!.state, DirectMediaBlobCustodyState.incomingAckPending);
      }

      // --- A fingerprinted strict-private row with NO v111 never reaches
      // the proof-less legacy transport in any state. ---
      {
        final fixture = await MediaRepositoryRealDbFixture.create();
        addTearDown(fixture.dispose);
        bridge = _FakeBridge();
        final staged = await stagePrivateIncoming(
          fixture: fixture,
          suffix: 'no-v111',
        );
        await fixture.db.delete(
          kDirectMediaBlobCustodyTable,
          where: 'attachment_id = ?',
          whereArgs: <Object?>[staged.attachment.id],
        );

        expect(
          await downloadMedia(
            bridge: bridge,
            mediaAttachmentRepo: fixture.repo,
            mediaFileManager: staged.manager,
            attachment: staged.attachment,
            contactPeerId: contactPeerId,
            owner: MediaOwnerLane.direct,
            messageRepo: fixture.messageRepo,
            intent: MediaDownloadIntent.explicitUser,
            nowMs: () => 1_800_000_100_000,
          ),
          isNull,
        );
        expect(bridge.commandLog, isEmpty);
        expect(
          (await fixture.rawAttachmentRow(
            staged.attachment.id,
          ))!['download_status'],
          kMediaDownloadStatusPending,
        );
      }

      // --- A pre-354 private parent with no fingerprint and no v111 keeps
      // the historical legacy explicit-download behavior. ---
      {
        final fixture = await MediaRepositoryRealDbFixture.create();
        addTearDown(fixture.dispose);
        bridge = _FakeBridge();
        const messageId = 'tc355-legacy-private';
        const attachmentId = 'tc355-legacy-private-blob';
        await fixture.seedDirectParent(messageId, contactPeerId: contactPeerId);
        await fixture.db.update(
          'messages',
          <String, Object?>{
            'private_media_policy_version': 1,
            'private_media_mode': 'protected',
            'private_media_state': 'available',
            'private_media_received_at_ms': 1_800_000_000_000,
            'private_media_clock_high_water_ms': 1_800_000_000_000,
          },
          where: 'id = ?',
          whereArgs: <Object?>[messageId],
        );
        final encrypted = _encryptedBytes(_jpegBytes);
        final legacy = MediaAttachment(
          id: attachmentId,
          messageId: messageId,
          mime: 'image/jpeg',
          size: _jpegBytes.length,
          mediaType: 'image',
          downloadStatus: kMediaDownloadStatusPending,
          createdAt: '2026-08-10T11:00:00.000Z',
          encryptionKeyBase64: _mediaKey,
          encryptionNonce: _mediaNonce,
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
          ownerLane: MediaOwnerLane.direct,
        );
        await fixture.repo.saveAttachment(legacy, owner: MediaOwnerLane.direct);
        bridge.downloadedBytes = encrypted;
        final manager = _CanonicalPathFakeMediaFileManager(tempDir.path);

        final legacyResult = await downloadMedia(
          bridge: bridge,
          mediaAttachmentRepo: fixture.repo,
          mediaFileManager: manager,
          attachment: legacy,
          contactPeerId: contactPeerId,
          owner: MediaOwnerLane.direct,
          messageRepo: fixture.messageRepo,
          intent: MediaDownloadIntent.explicitUser,
          nowMs: () => 1_800_000_100_000,
        );

        expect(legacyResult, isNotNull);
        expect(bridge.commandLog, contains('media:download'));
      }
    });

    test('TC-355-02a private strict path guard and deterministic staging '
        'preserve retry authority', () async {
      // --- An unsafe symlink at ANY authorized target refuses before the
      // claim and before any network work. ---
      for (final unsafe in const <String>[
        '',
        '.enc',
        '.private.enc',
        '.private.enc.dec',
      ]) {
        final fixture = await MediaRepositoryRealDbFixture.create();
        addTearDown(fixture.dispose);
        bridge = _FakeBridge();
        final staged = await stagePrivateIncoming(
          fixture: fixture,
          suffix: 'unsafe${unsafe.replaceAll('.', '-')}',
        );
        wireRelay(
          attachment: staged.attachment,
          custody: staged.custody,
          ciphertext: staged.ciphertext,
        );
        final outside = File('${tempDir.path}/outside-$unsafe.bin')
          ..writeAsBytesSync(const <int>[7, 7, 7]);
        final link = '${staged.canonicalAbsolutePath}$unsafe';
        await Directory(File(link).parent.path).create(recursive: true);
        Link(link).createSync(outside.path);

        expect(
          await downloadMedia(
            bridge: bridge,
            mediaAttachmentRepo: fixture.repo,
            mediaFileManager: staged.manager,
            attachment: staged.attachment,
            contactPeerId: contactPeerId,
            owner: MediaOwnerLane.direct,
            messageRepo: fixture.messageRepo,
            intent: MediaDownloadIntent.explicitUser,
            nowMs: () => 1_800_000_100_000,
          ),
          isNull,
          reason: 'unsafe target "$unsafe"',
        );
        expect(bridge.commandLog, isEmpty, reason: unsafe);
        expect(
          (await fixture.rawAttachmentRow(
            staged.attachment.id,
          ))!['download_status'],
          kMediaDownloadStatusPending,
          reason: 'no durable claim may survive a refused preflight',
        );
        expect(outside.readAsBytesSync(), const <int>[7, 7, 7]);
      }

      // --- An arbitrary bridge-returned decrypt path is never stat-ed,
      // deleted, renamed or promoted; the claim is released to retryable
      // and v111 survives. ---
      {
        final fixture = await MediaRepositoryRealDbFixture.create();
        addTearDown(fixture.dispose);
        bridge = _FakeBridge();
        final staged = await stagePrivateIncoming(
          fixture: fixture,
          suffix: 'arbitrary-decrypt',
        );
        wireRelay(
          attachment: staged.attachment,
          custody: staged.custody,
          ciphertext: staged.ciphertext,
        );
        final foreign = File('${tempDir.path}/foreign-plaintext.bin')
          ..writeAsBytesSync(_jpegBytes);
        bridge.decryptResponse = <String, dynamic>{
          'ok': true,
          'decryptedPath': foreign.path,
        };

        expect(
          await downloadMedia(
            bridge: bridge,
            mediaAttachmentRepo: fixture.repo,
            mediaFileManager: staged.manager,
            attachment: staged.attachment,
            contactPeerId: contactPeerId,
            owner: MediaOwnerLane.direct,
            messageRepo: fixture.messageRepo,
            intent: MediaDownloadIntent.explicitUser,
            nowMs: () => 1_800_000_100_000,
          ),
          isNull,
        );
        expect(
          foreign.existsSync(),
          isTrue,
          reason: 'a foreign decrypt target is never deleted or renamed',
        );
        expect(foreign.readAsBytesSync(), _jpegBytes);
        expect(File(staged.canonicalAbsolutePath).existsSync(), isFalse);
        expect(bridge.deleteRequests, isEmpty);
        final row = await fixture.rawAttachmentRow(staged.attachment.id);
        expect(row!['download_status'], kMediaDownloadStatusDownloadFailed);
        expect(row['local_path'], isNull);
        expect(
          (await (fixture.repo as DirectMediaBlobCustodyRepository)
                  .loadIncomingDirectMediaBlobCustodyForAttachment(
                    staged.attachment.id,
                  ))!
              .state,
          DirectMediaBlobCustodyState.incomingCommitted,
        );
      }

      // --- A LAN transfer that loses its final CAS keeps the byte-identical
      // LAN source, removes only attempt-owned candidates, releases the row
      // to retryable, retains v111 and makes zero relay calls. ---
      {
        final fixture = await MediaRepositoryRealDbFixture.create();
        addTearDown(fixture.dispose);
        bridge = _FakeBridge();
        final staged = await stagePrivateIncoming(
          fixture: fixture,
          suffix: 'lan-cas-loss',
        );
        final lanSource = File('${staged.canonicalAbsolutePath}.enc');
        await lanSource.parent.create(recursive: true);
        await lanSource.writeAsBytes(staged.ciphertext, flush: true);
        // Hiding the parent makes the final local-path CAS refuse while the
        // ciphertext is already normalized into the deterministic pair.
        await fixture.db.update(
          'messages',
          <String, Object?>{'hidden_at': '2026-08-10T11:05:00.000Z'},
          where: 'id = ?',
          whereArgs: <Object?>[staged.attachment.messageId],
        );

        expect(
          await downloadMedia(
            bridge: bridge,
            mediaAttachmentRepo: fixture.repo,
            mediaFileManager: staged.manager,
            attachment: staged.attachment,
            contactPeerId: contactPeerId,
            owner: MediaOwnerLane.direct,
            messageRepo: fixture.messageRepo,
            intent: MediaDownloadIntent.explicitUser,
            nowMs: () => 1_800_000_100_000,
          ),
          isNull,
        );
        expect(
          lanSource.existsSync(),
          isTrue,
          reason: 'the only retry source must survive a lost commit',
        );
        expect(lanSource.readAsBytesSync(), staged.ciphertext);
        expect(
          File('${staged.canonicalAbsolutePath}.private.enc').existsSync(),
          isFalse,
        );
        expect(
          File('${staged.canonicalAbsolutePath}.private.enc.dec').existsSync(),
          isFalse,
        );
        expect(File(staged.canonicalAbsolutePath).existsSync(), isFalse);
        expect(bridge.commandLog, isNot(contains('media:download')));
        expect(bridge.deleteRequests, isEmpty);
        expect(
          (await (fixture.repo as DirectMediaBlobCustodyRepository)
                  .loadIncomingDirectMediaBlobCustodyForAttachment(
                    staged.attachment.id,
                  ))!
              .state,
          DirectMediaBlobCustodyState.incomingCommitted,
        );
      }

      // --- Exact terminal private cleanup still removes the legacy LAN
      // source it deliberately preserved for retry. ---
      {
        final fixture = await MediaRepositoryRealDbFixture.create();
        addTearDown(fixture.dispose);
        final staged = await stagePrivateIncoming(
          fixture: fixture,
          suffix: 'terminal-cleanup',
        );
        final lanSource = File('${staged.canonicalAbsolutePath}.enc');
        await lanSource.parent.create(recursive: true);
        await lanSource.writeAsBytes(staged.ciphertext, flush: true);
        final lifecycle = DirectPrivateMediaLifecycle(
          messageRepository: fixture.messageRepo,
          mediaAttachmentRepository: fixture.repo,
          mediaFileManager: staged.manager,
        );
        await fixture.db.update(
          'messages',
          <String, Object?>{
            'private_media_state': 'consumed',
            'private_media_terminal_at_ms': 1_800_000_200_000,
          },
          where: 'id = ?',
          whereArgs: <Object?>[staged.attachment.messageId],
        );
        final engine = PrivateMediaLifecycleEngine(
          adapter: lifecycle,
          lifecycleLock: fixture.repo.lifecycleLock,
          nowMs: () => 1_800_000_300_000,
        );
        expect(
          (await engine.reconcileLocalLifecycle()).cleanupCompleted,
          greaterThanOrEqualTo(1),
        );
        expect(
          lanSource.existsSync(),
          isFalse,
          reason: 'terminal cleanup remains destructive for the LAN source',
        );
      }
    });

    /// Stages one durable v1 disappearing initial with an explicit
    /// receiver-local clock and its independent v111 transport lease.
    Future<
      ({
        MediaAttachment attachment,
        DirectMediaBlobCustodyRow custody,
        _CanonicalPathFakeMediaFileManager manager,
        String canonicalAbsolutePath,
        List<int> ciphertext,
        String messageId,
      })
    >
    stageDisappearingIncoming({
      required MediaRepositoryRealDbFixture fixture,
      required String suffix,
      int durationSeconds = 3600,
      int receivedAtMs = 1_800_000_000_000,
      int blobExpiresAtMs = 1_900_005_000_000,
    }) async {
      final messageId = 'tc358-msg-$suffix';
      final attachmentId = 'tc358-blob-$suffix';
      final encrypted = _encryptedBytes(_jpegBytes);
      final contentHash = _hashBytes(encrypted);
      final commitment = DirectMediaBlobCustodyCommitment(
        contentHash: contentHash,
        ciphertextSize: encrypted.length,
        expiresAtMs: blobExpiresAtMs,
      );
      final attachment = MediaAttachment(
        id: attachmentId,
        messageId: messageId,
        mime: 'image/jpeg',
        size: _jpegBytes.length,
        mediaType: 'image',
        downloadStatus: kMediaDownloadStatusPending,
        createdAt: '2026-08-11T11:00:00.000Z',
        contentHash: contentHash,
        encryptionKeyBase64: _mediaKey,
        encryptionNonce: _mediaNonce,
        encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
        blobCustody: commitment,
        ownerLane: MediaOwnerLane.direct,
      );
      final custody = DirectMediaBlobCustodyRow(
        attachmentId: attachmentId,
        messageId: messageId,
        direction: DirectMediaBlobCustodyDirection.incoming,
        state: DirectMediaBlobCustodyState.incomingCommitted,
        inboxCustodyIncarnationId: null,
        recipientPeerId: null,
        ciphertextRelativePath: null,
        contentHash: contentHash,
        ciphertextSize: encrypted.length,
        expiresAtMs: blobExpiresAtMs,
        custodyRelayPeerId: null,
        lastAttemptAt: null,
        nextAttemptAt: null,
        createdAt: '2026-08-11T11:00:00.000Z',
        updatedAt: '2026-08-11T11:00:00.000Z',
      );
      final message = ConversationMessage(
        id: messageId,
        contactPeerId: contactPeerId,
        senderPeerId: contactPeerId,
        text: '',
        timestamp: '2026-08-11T11:00:00.000Z',
        status: 'delivered',
        isIncoming: true,
        createdAt: '2026-08-11T11:00:00.000Z',
        privateMediaPolicy: PrivateMediaPolicy.disappearing(durationSeconds),
        privateMediaState: PrivateMediaLifecycleState.available,
        privateMediaReceivedAtMs: receivedAtMs,
        privateMediaExpiresAtMs: receivedAtMs + durationSeconds * 1000,
        privateMediaClockHighWaterMs: receivedAtMs,
      );
      final stage =
          await (fixture.repo
                  as IncomingDirectPrivateMediaBlobCustodyRepository)
              .stageIncomingDirectPrivateMediaBlobCustody(
                message: message,
                attachment: attachment,
                custodyRow: custody,
              );
      expect(stage.outcome.name, 'applied', reason: suffix);
      final manager = _CanonicalPathFakeMediaFileManager(tempDir.path);
      return (
        attachment: attachment,
        custody: custody,
        manager: manager,
        canonicalAbsolutePath: await manager.localPathForAttachment(
          contactPeerId: contactPeerId,
          blobId: attachmentId,
          mime: 'image/jpeg',
        ),
        ciphertext: encrypted,
        messageId: messageId,
      );
    }

    test('TC-358-04a disappearing strict download requalifies deadline before '
        'shortcuts and final commit', () async {
      const deadlineMs = 1_800_000_000_000 + 3600 * 1000;

      // 1. Before the deadline the relay lane commits `done` +
      //    `incoming_ack_pending` BEFORE the source-pinned ACK.
      {
        final fixture = await MediaRepositoryRealDbFixture.create();
        addTearDown(fixture.dispose);
        bridge = _FakeBridge();
        final staged = await stageDisappearingIncoming(
          fixture: fixture,
          suffix: 'relay',
        );
        wireRelay(
          attachment: staged.attachment,
          custody: staged.custody,
          ciphertext: staged.ciphertext,
        );
        var ackSawDurableCommit = false;
        bridge.onDeleteRequest = () async {
          final row = await fixture.rawAttachmentRow(staged.attachment.id);
          final pending =
              await (fixture.repo as DirectMediaBlobCustodyRepository)
                  .loadIncomingDirectMediaBlobCustodyForAttachment(
                    staged.attachment.id,
                  );
          ackSawDurableCommit =
              row!['download_status'] == kMediaDownloadStatusDone &&
              row['local_path'] != null &&
              pending!.state == DirectMediaBlobCustodyState.incomingAckPending;
        };
        final downloaded = await downloadMedia(
          bridge: bridge,
          mediaAttachmentRepo: fixture.repo,
          mediaFileManager: staged.manager,
          attachment: staged.attachment,
          contactPeerId: contactPeerId,
          owner: MediaOwnerLane.direct,
          messageRepo: fixture.messageRepo,
          intent: MediaDownloadIntent.explicitUser,
          nowMs: () => deadlineMs - 1000,
        );
        expect(downloaded, isNotNull);
        expect(downloaded!.downloadStatus, kMediaDownloadStatusDone);
        expect(ackSawDurableCommit, isTrue);
        expect(
          File(staged.canonicalAbsolutePath).readAsBytesSync(),
          _jpegBytes,
        );
        final parent = (await fixture.db.query(
          'messages',
          where: 'id = ?',
          whereArgs: <Object?>[staged.messageId],
        )).single;
        expect(parent['private_media_state'], 'available');
        expect(parent['private_media_expires_at_ms'], deadlineMs);
      }

      // 2. A passed deadline refuses BEFORE any network, ACK or plaintext,
      //    for the committed/no-local shortcut.
      {
        final fixture = await MediaRepositoryRealDbFixture.create();
        addTearDown(fixture.dispose);
        bridge = _FakeBridge();
        final staged = await stageDisappearingIncoming(
          fixture: fixture,
          suffix: 'deadline-first',
        );
        wireRelay(
          attachment: staged.attachment,
          custody: staged.custody,
          ciphertext: staged.ciphertext,
        );
        expect(
          await downloadMedia(
            bridge: bridge,
            mediaAttachmentRepo: fixture.repo,
            mediaFileManager: staged.manager,
            attachment: staged.attachment,
            contactPeerId: contactPeerId,
            owner: MediaOwnerLane.direct,
            messageRepo: fixture.messageRepo,
            intent: MediaDownloadIntent.explicitUser,
            nowMs: () => deadlineMs + 1000,
          ),
          isNull,
        );
        expect(
          bridge.commandLog,
          isEmpty,
          reason: 'a passed deadline performs zero network work',
        );
        expect(File(staged.canonicalAbsolutePath).existsSync(), isFalse);
        expect(
          await (fixture.repo as DirectMediaBlobCustodyRepository)
              .loadIncomingDirectMediaBlobCustodyForAttachment(
                staged.attachment.id,
              ),
          isNotNull,
          reason: 'the independent v111 lease is never ACKed or deleted',
        );
      }

      // 3. Every already-local shortcut requalifies the deadline too.
      for (final shortcut in const <String>[
        'ack-pending-local',
        'committed-local',
        'blob-expired',
      ]) {
        final fixture = await MediaRepositoryRealDbFixture.create();
        addTearDown(fixture.dispose);
        bridge = _FakeBridge();
        final staged = await stageDisappearingIncoming(
          fixture: fixture,
          suffix: shortcut,
          blobExpiresAtMs: shortcut == 'blob-expired'
              ? deadlineMs - 100_000
              : 1_900_005_000_000,
        );
        if (shortcut != 'blob-expired') {
          // A durable local plaintext copy already exists.
          final canonical = File(staged.canonicalAbsolutePath);
          await canonical.parent.create(recursive: true);
          canonical.writeAsBytesSync(_jpegBytes, flush: true);
          await fixture.db.update(
            'media_attachments',
            <String, Object?>{
              'download_status': kMediaDownloadStatusDone,
              'local_path': staged.manager.relativePathForAttachment(
                contactPeerId: contactPeerId,
                blobId: staged.attachment.id,
                mime: 'image/jpeg',
              ),
            },
            where: 'id = ?',
            whereArgs: <Object?>[staged.attachment.id],
          );
        }
        if (shortcut == 'ack-pending-local') {
          expect(
            await (fixture.repo as DirectMediaBlobCustodyRepository)
                .transitionDirectMediaBlobCustodyIfExact(
                  expected: staged.custody,
                  next: staged.custody.copyWith(
                    state: DirectMediaBlobCustodyState.incomingAckPending,
                    custodyRelayPeerId: relayPeerId,
                    updatedAt: '2026-08-11T11:00:01.000Z',
                  ),
                ),
            isTrue,
          );
        }
        final refreshed = (await fixture.repo.getAttachmentsForMessage(
          staged.messageId,
          owner: MediaOwnerLane.direct,
        )).single;
        expect(
          await downloadMedia(
            bridge: bridge,
            mediaAttachmentRepo: fixture.repo,
            mediaFileManager: staged.manager,
            attachment: refreshed,
            contactPeerId: contactPeerId,
            owner: MediaOwnerLane.direct,
            messageRepo: fixture.messageRepo,
            intent: MediaDownloadIntent.explicitUser,
            nowMs: () => deadlineMs + 1000,
          ),
          isNull,
          reason: shortcut,
        );
        expect(bridge.commandLog, isEmpty, reason: shortcut);
        final parent = (await fixture.db.query(
          'messages',
          where: 'id = ?',
          whereArgs: <Object?>[staged.messageId],
        )).single;
        expect(
          parent['private_media_state'],
          'expired',
          reason: 'the shortcut advanced the receiver clock ($shortcut)',
        );
        expect(
          await (fixture.repo as DirectMediaBlobCustodyRepository)
              .loadIncomingDirectMediaBlobCustodyForAttachment(
                staged.attachment.id,
              ),
          isNotNull,
          reason:
              'content expiry never converges the transport lease '
              '($shortcut)',
        );
      }

      // 4. Automatic intent stays refused for disappearing media.
      {
        final fixture = await MediaRepositoryRealDbFixture.create();
        addTearDown(fixture.dispose);
        bridge = _FakeBridge();
        final staged = await stageDisappearingIncoming(
          fixture: fixture,
          suffix: 'automatic',
        );
        wireRelay(
          attachment: staged.attachment,
          custody: staged.custody,
          ciphertext: staged.ciphertext,
        );
        expect(
          await downloadMedia(
            bridge: bridge,
            mediaAttachmentRepo: fixture.repo,
            mediaFileManager: staged.manager,
            attachment: staged.attachment,
            contactPeerId: contactPeerId,
            owner: MediaOwnerLane.direct,
            messageRepo: fixture.messageRepo,
            nowMs: () => deadlineMs - 1000,
          ),
          isNull,
        );
        expect(bridge.commandLog, isEmpty);
      }
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
