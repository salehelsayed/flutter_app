import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';
import 'package:flutter_app/core/database/direct_media_blob_custody.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart'
    show kMediaDownloadStatusDone;
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';

typedef StrictGroupMediaBlobBeforeSourcePinnedAck =
    FutureOr<void> Function(DirectMediaBlobCustodyRow row);

/// Process-scoped single-flight owner for one strict incoming group blob.
///
/// A second caller may join only when it names the same immutable attachment
/// projection. A stale or crossed projection fails closed instead of racing a
/// decrypt/promotion sequence against the same canonical plaintext path.
final class StrictGroupMediaBlobDownloadCoordinator {
  final Map<_StrictGroupDownloadScope, _StrictGroupDownloadInFlight> _inFlight =
      <_StrictGroupDownloadScope, _StrictGroupDownloadInFlight>{};

  Future<MediaAttachment?> run({
    required Bridge bridge,
    required MediaAttachmentRepository mediaAttachmentRepository,
    required MediaFileManager mediaFileManager,
    required MediaAttachment attachment,
    required String groupId,
    required Future<MediaAttachment?> Function() operation,
  }) {
    final scope = _StrictGroupDownloadScope(
      bridge: bridge,
      mediaAttachmentRepository: mediaAttachmentRepository,
      mediaFileManager: mediaFileManager,
      attachmentId: attachment.id,
    );
    final discriminator = _StrictGroupDownloadDiscriminator(
      groupId: groupId,
      messageId: attachment.messageId,
      mime: attachment.mime,
      plaintextSize: attachment.size,
      contentHash: attachment.contentHash,
      encryptionKeyBase64: attachment.encryptionKeyBase64,
      encryptionNonce: attachment.encryptionNonce,
      encryptionScheme: attachment.encryptionScheme,
      custodyFingerprint: attachment.groupMediaBlobCustodyFingerprint,
    );
    final active = _inFlight[scope];
    if (active != null) {
      return active.discriminator == discriminator
          ? active.future
          : Future<MediaAttachment?>.value(null);
    }

    late final Future<MediaAttachment?> shared;
    shared = Future<MediaAttachment?>.sync(operation).whenComplete(() {
      final current = _inFlight[scope];
      if (current != null && identical(current.future, shared)) {
        _inFlight.remove(scope);
      }
    });
    _inFlight[scope] = _StrictGroupDownloadInFlight(
      discriminator: discriminator,
      future: shared,
    );
    return shared;
  }
}

final StrictGroupMediaBlobDownloadCoordinator
_processStrictGroupMediaBlobDownloadCoordinator =
    StrictGroupMediaBlobDownloadCoordinator();

/// Sole feature owner of strict group blob download, durable promotion and
/// source-pinned ACK.
///
/// A fingerprinted group row never invokes the proof-less group transport.
/// Ciphertext receipt/hash/size, AES-GCM decryption and a flushed/reopened
/// plaintext are all proven before the one atomic READY + ACK_PENDING commit.
/// ACK failure only advances durable retry metadata; restart therefore retries
/// the exact persisted relay source and never downloads or decrypts again.
final class StrictGroupMediaBlobDownloadAckOwner {
  StrictGroupMediaBlobDownloadAckOwner({
    required this.bridge,
    required this.mediaAttachmentRepository,
    required this.mediaFileManager,
    StrictGroupMediaBlobDownloadCoordinator? downloadCoordinator,
    this.beforeSourcePinnedAck,
    DateTime Function()? now,
  }) : downloadCoordinator =
           downloadCoordinator ??
           _processStrictGroupMediaBlobDownloadCoordinator,
       now = now ?? DateTime.now;

  final Bridge bridge;
  final MediaAttachmentRepository mediaAttachmentRepository;
  final MediaFileManager mediaFileManager;
  final StrictGroupMediaBlobDownloadCoordinator downloadCoordinator;
  final StrictGroupMediaBlobBeforeSourcePinnedAck? beforeSourcePinnedAck;
  final DateTime Function() now;

  GroupMediaBlobCustodyRepository? get _repository =>
      mediaAttachmentRepository is GroupMediaBlobCustodyRepository
      ? mediaAttachmentRepository as GroupMediaBlobCustodyRepository
      : null;

  Future<MediaAttachment?> downloadAndAcknowledge({
    required MediaAttachment attachment,
    required String groupId,
  }) => downloadCoordinator.run(
    bridge: bridge,
    mediaAttachmentRepository: mediaAttachmentRepository,
    mediaFileManager: mediaFileManager,
    attachment: attachment,
    groupId: groupId,
    operation: () =>
        _downloadAndAcknowledge(attachment: attachment, groupId: groupId),
  );

  Future<MediaAttachment?> _downloadAndAcknowledge({
    required MediaAttachment attachment,
    required String groupId,
  }) async {
    final repository = _repository;
    if (repository == null ||
        !repository.supportsGroupMediaBlobCustody ||
        groupId.trim().isEmpty ||
        groupId != groupId.trim() ||
        attachment.messageId.trim().isEmpty ||
        attachment.ownerLane != MediaOwnerLane.group ||
        attachment.groupMediaBlobCustodyFingerprint == null ||
        !attachment.hasEncryptionMetadata) {
      return null;
    }

    final currentAttachment = await _loadExactCurrentAttachment(
      attachment: attachment,
    );
    if (currentAttachment == null) return null;
    var custody = await _loadExactIncomingCustody(
      repository: repository,
      attachment: currentAttachment,
      groupId: groupId,
    );
    if (custody == null) return null;

    final nowMs = now().toUtc().millisecondsSinceEpoch;
    if (custody.expiresAtMs! <= nowMs) {
      await repository.deleteIncomingGroupMediaBlobIfExpired(
        expected: custody,
        nowMs: nowMs,
      );
      return _loadDurableLocalAttachment(
        messageId: currentAttachment.messageId,
        attachmentId: currentAttachment.id,
      );
    }
    if (custody.state == DirectMediaBlobCustodyState.incomingAckPending) {
      final durable = await _loadDurableLocalAttachment(
        messageId: currentAttachment.messageId,
        attachmentId: currentAttachment.id,
      );
      if (durable == null) return null;
      await _acknowledgeReloadedPending(custody);
      return _loadDurableLocalAttachment(
        messageId: currentAttachment.messageId,
        attachmentId: currentAttachment.id,
      );
    }
    if (custody.state != DirectMediaBlobCustodyState.incomingCommitted) {
      return null;
    }

    // An exact local plaintext with no persisted source is not authority to
    // retire a relay blob. Keep the committed row until expiry rather than
    // manufacturing an ACK source or re-downloading through a legacy path.
    final alreadyLocal = await _loadDurableLocalAttachment(
      messageId: currentAttachment.messageId,
      attachmentId: currentAttachment.id,
    );
    if (alreadyLocal != null) return alreadyLocal;

    final absolutePath = await mediaFileManager.localPathForAttachment(
      contactPeerId: groupId,
      blobId: currentAttachment.id,
      mime: currentAttachment.mime,
    );
    final relativePath = mediaFileManager.relativePathForAttachment(
      contactPeerId: groupId,
      blobId: currentAttachment.id,
      mime: currentAttachment.mime,
    );
    final ciphertext = File(
      '$absolutePath.group-strict-${now().toUtc().microsecondsSinceEpoch}.enc',
    );
    final decrypted = File('${ciphertext.path}.dec');
    await ciphertext.parent.create(recursive: true);
    await _deleteRegularFile(ciphertext);
    await _deleteRegularFile(decrypted);

    String? sourceRelayPeerId;
    try {
      final result = await callP2PMediaDownload(
        bridge,
        id: custody.custodyBlobId,
        outputPath: ciphertext.path,
        custodyKind: custody.custodyKind,
        custodyContract: custody.custodyContract,
        contentHash: custody.contentHash,
        size: custody.ciphertextSize,
        mime: custody.transportMime,
        expiresAtMs: custody.expiresAtMs,
        payloadSizeBytes: custody.ciphertextSize,
      );
      if (!_isExactGroupDownloadReceipt(result, custody) ||
          !await _matchesCiphertext(ciphertext, custody)) {
        return null;
      }
      sourceRelayPeerId = result['custodyRelayPeerId'] as String;

      final expectedCustody = custody;
      final committed = await repository.runGroupMediaBlobCustodyLifecycle(
        () async {
          final currentCustody = await _loadExactIncomingCustody(
            repository: repository,
            attachment: currentAttachment,
            groupId: groupId,
          );
          if (currentCustody == null ||
              !currentCustody.exactDatabaseProjectionMatches(expectedCustody)) {
            return false;
          }
          final decryptedPath = await callBlobDecrypt(
            bridge,
            filePath: ciphertext.path,
            keyBase64: currentAttachment.encryptionKeyBase64!,
            nonce: currentAttachment.encryptionNonce!,
          );
          // The bridge-returned path is untrusted. The native contract owns
          // exactly this sibling; no other path is stat-ed, renamed or deleted.
          if (decryptedPath != decrypted.path ||
              !await _isReadablePlaintext(
                decrypted,
                expectedSize: currentAttachment.size,
              )) {
            return false;
          }
          final canonical = File(absolutePath);
          await canonical.parent.create(recursive: true);
          await _deleteRegularFile(canonical);
          await decrypted.rename(canonical.path);
          await _flushFile(canonical);
          if (!await _isReadablePlaintext(
            canonical,
            expectedSize: currentAttachment.size,
          )) {
            await _deleteRegularFile(canonical);
            return false;
          }
          final commitAt = now().toUtc();
          final didCommit = await repository
              .commitIncomingGroupMediaBlobLocalPath(
                expectedAttachment: currentAttachment,
                expectedCustody: expectedCustody,
                localPath: relativePath,
                sourceRelayPeerId: sourceRelayPeerId!,
                updatedAt: commitAt.toIso8601String(),
                nowMs: commitAt.millisecondsSinceEpoch,
              );
          if (!didCommit) {
            await _deleteRegularFile(canonical);
            return false;
          }
          return true;
        },
      );
      if (!committed) return null;
    } on Object {
      // Every strict failure retains its exact incoming row and never invokes
      // the proof-less group download/delete transport.
      return null;
    } finally {
      await _deleteRegularFile(ciphertext);
      await _deleteRegularFile(decrypted);
    }

    custody = await _loadExactIncomingCustody(
      repository: repository,
      attachment: currentAttachment,
      groupId: groupId,
    );
    if (custody != null &&
        custody.state == DirectMediaBlobCustodyState.incomingAckPending) {
      await _acknowledgeReloadedPending(custody);
    }
    return _loadDurableLocalAttachment(
      messageId: currentAttachment.messageId,
      attachmentId: currentAttachment.id,
    );
  }

  /// Converges blobs for a message whose local delete-for-me tombstone and
  /// journal entries have already committed.
  ///
  /// A committed row performs a strict ciphertext download only to obtain and
  /// verify its exact relay source. It never decrypts or promotes plaintext.
  /// The repository then atomically proves the delete journal/tombstone,
  /// terminalizes the local attachment projection and records ACK_PENDING.
  /// Only that durable transition permits the source-pinned ACK below.
  Future<bool> terminalizeLocallyDeletedMessage({
    required String groupId,
    required String messageId,
  }) async {
    final repository = _repository;
    if (repository == null ||
        !repository.supportsGroupMediaBlobCustody ||
        groupId.trim().isEmpty ||
        groupId != groupId.trim() ||
        messageId.trim().isEmpty ||
        messageId != messageId.trim()) {
      return false;
    }
    final rows =
        (await repository.loadGroupMediaBlobCustodyForMessage(
              groupId: groupId,
              messageId: messageId,
            ))
            .where(
              (row) =>
                  row.ownerLane == MediaBlobCustodyOwnerLane.group &&
                  row.groupId == groupId &&
                  row.messageId == messageId &&
                  row.direction == DirectMediaBlobCustodyDirection.incoming,
            )
            .toList(growable: false)
          ..sort((left, right) {
            final attachmentOrder = left.attachmentId.compareTo(
              right.attachmentId,
            );
            return attachmentOrder != 0
                ? attachmentOrder
                : left.custodyBlobId.compareTo(right.custodyBlobId);
          });
    for (final initial in rows) {
      if (initial.state == DirectMediaBlobCustodyState.incomingAckPending) {
        await _acknowledgeReloadedPending(initial);
        continue;
      }
      if (initial.state != DirectMediaBlobCustodyState.incomingCommitted) {
        continue;
      }
      final attachments = await mediaAttachmentRepository
          .getAttachmentsForMessage(messageId, owner: MediaOwnerLane.group);
      final exact = attachments.where(
        (attachment) => attachment.id == initial.attachmentId,
      );
      if (exact.length != 1) continue;
      final attachment = exact.single;
      if (attachment.groupMediaBlobCustodyFingerprint == null ||
          attachment.contentHash != initial.contentHash ||
          attachment.ownerLane != MediaOwnerLane.group) {
        continue;
      }
      final nowMs = now().toUtc().millisecondsSinceEpoch;
      if (initial.expiresAtMs! <= nowMs) {
        await repository.deleteIncomingGroupMediaBlobIfExpired(
          expected: initial,
          nowMs: nowMs,
        );
        continue;
      }

      final canonical = await mediaFileManager.localPathForAttachment(
        contactPeerId: groupId,
        blobId: attachment.id,
        mime: attachment.mime,
      );
      final ciphertext = File(
        '$canonical.group-delete-${now().toUtc().microsecondsSinceEpoch}.enc',
      );
      await ciphertext.parent.create(recursive: true);
      await _deleteRegularFile(ciphertext);
      try {
        final result = await callP2PMediaDownload(
          bridge,
          id: initial.custodyBlobId,
          outputPath: ciphertext.path,
          custodyKind: initial.custodyKind,
          custodyContract: initial.custodyContract,
          contentHash: initial.contentHash,
          size: initial.ciphertextSize,
          mime: initial.transportMime,
          expiresAtMs: initial.expiresAtMs,
          payloadSizeBytes: initial.ciphertextSize,
        );
        if (!_isExactGroupDownloadReceipt(result, initial) ||
            !await _matchesCiphertext(ciphertext, initial)) {
          continue;
        }
        final transitioned = await repository
            .terminalizeIncomingGroupMediaBlobForLocalDeletion(
              expectedAttachment: attachment,
              expectedCustody: initial,
              sourceRelayPeerId: result['custodyRelayPeerId'] as String,
              updatedAt: now().toUtc().toIso8601String(),
            );
        if (!transitioned) continue;
        final pending = await repository.loadGroupMediaBlobCustodyForTarget(
          groupId: groupId,
          attachmentId: initial.attachmentId,
          custodyBlobId: initial.custodyBlobId,
          direction: DirectMediaBlobCustodyDirection.incoming,
        );
        if (pending != null &&
            pending.state == DirectMediaBlobCustodyState.incomingAckPending) {
          await _acknowledgeReloadedPending(pending);
        }
      } on Object {
        // Tombstone + journal remain the durable local suppression authority;
        // a later delete/lifecycle retry reuses the exact committed row.
      } finally {
        await _deleteRegularFile(ciphertext);
      }
    }
    final remaining = await repository.loadGroupMediaBlobCustodyForMessage(
      groupId: groupId,
      messageId: messageId,
    );
    return remaining.every(
      (row) =>
          row.ownerLane != MediaBlobCustodyOwnerLane.group ||
          row.direction != DirectMediaBlobCustodyDirection.incoming ||
          row.state != DirectMediaBlobCustodyState.incomingCommitted,
    );
  }

  /// Bounded lifecycle drain for crash/ACK-failure recovery. Rows are loaded
  /// only from the group ACK_PENDING lane; each request uses the row's exact
  /// persisted source relay and proof tuple. A not-yet-due retry is left
  /// untouched and cannot starve later due rows in the bounded page.
  Future<int> retryPendingAcknowledgements({int limit = 50}) async {
    final repository = _repository;
    if (repository == null ||
        !repository.supportsGroupMediaBlobCustody ||
        limit <= 0) {
      return 0;
    }
    final rows = await repository.loadGroupMediaBlobCustodyByStates(
      const <DirectMediaBlobCustodyState>{
        DirectMediaBlobCustodyState.incomingAckPending,
      },
      limit: limit,
    );
    final nowUtc = now().toUtc();
    var acknowledged = 0;
    for (final row in rows) {
      if (row.ownerLane != MediaBlobCustodyOwnerLane.group ||
          row.direction != DirectMediaBlobCustodyDirection.incoming ||
          row.state != DirectMediaBlobCustodyState.incomingAckPending ||
          row.custodyRelayPeerId == null) {
        continue;
      }
      final expiresAtMs = row.expiresAtMs;
      if (expiresAtMs != null && expiresAtMs <= nowUtc.millisecondsSinceEpoch) {
        if (await repository.deleteIncomingGroupMediaBlobIfExpired(
          expected: row,
          nowMs: nowUtc.millisecondsSinceEpoch,
        )) {
          acknowledged++;
        }
        continue;
      }
      final nextAttemptAt = row.nextAttemptAt;
      if (nextAttemptAt != null) {
        final due = DateTime.tryParse(nextAttemptAt)?.toUtc();
        if (due == null || due.isAfter(nowUtc)) continue;
      }
      if (await _acknowledgeReloadedPending(row)) acknowledged++;
    }
    return acknowledged;
  }

  /// Retries an already-durable ACK against only its persisted relay source.
  /// Exact `acked` and `already_acked` receipts retire the row; failure keeps
  /// it ACK-pending with bounded exponential retry metadata.
  Future<bool> acknowledgePending(DirectMediaBlobCustodyRow expected) async {
    final repository = _repository;
    if (repository == null ||
        !repository.supportsGroupMediaBlobCustody ||
        expected.ownerLane != MediaBlobCustodyOwnerLane.group ||
        expected.direction != DirectMediaBlobCustodyDirection.incoming ||
        expected.state != DirectMediaBlobCustodyState.incomingAckPending ||
        expected.custodyKind != kGroupMediaBlobCustodyKind ||
        expected.custodyRelayPeerId == null) {
      return false;
    }
    try {
      final result = await callP2PMediaDelete(
        bridge,
        id: expected.custodyBlobId,
        custodyKind: expected.custodyKind,
        custodyContract: expected.custodyContract,
        contentHash: expected.contentHash,
        size: expected.ciphertextSize,
        mime: expected.transportMime,
        expiresAtMs: expected.expiresAtMs,
        custodyRelayPeerId: expected.custodyRelayPeerId,
      );
      if (_isExactGroupAckReceipt(result, expected)) {
        return repository.deleteIncomingGroupMediaBlobAckPendingIfExact(
          expected,
        );
      }
    } on Object {
      // Persist the retry projection below.
    }

    final attemptAt = now().toUtc();
    final retryCount = expected.retryCount + 1;
    final exponent = math.min(retryCount, 8);
    final delaySeconds = math.min(300, 1 << exponent);
    await repository.transitionGroupMediaBlobCustodyIfExact(
      expected: expected,
      next: expected.copyWith(
        retryCount: retryCount,
        lastAttemptAt: attemptAt.toIso8601String(),
        nextAttemptAt: attemptAt
            .add(Duration(seconds: delaySeconds))
            .toIso8601String(),
        updatedAt: attemptAt.toIso8601String(),
      ),
    );
    return false;
  }

  Future<bool> _acknowledgeReloadedPending(
    DirectMediaBlobCustodyRow reloaded,
  ) async {
    if (reloaded.state != DirectMediaBlobCustodyState.incomingAckPending ||
        reloaded.custodyRelayPeerId == null) {
      return false;
    }
    await beforeSourcePinnedAck?.call(reloaded);
    return acknowledgePending(reloaded);
  }

  Future<MediaAttachment?> _loadExactCurrentAttachment({
    required MediaAttachment attachment,
  }) async {
    final candidates = await mediaAttachmentRepository.getAttachmentsForMessage(
      attachment.messageId,
      owner: MediaOwnerLane.group,
    );
    final exact = candidates.where(
      (candidate) => candidate.id == attachment.id,
    );
    if (exact.length != 1) return null;
    final current = exact.single;
    if (current.messageId != attachment.messageId ||
        current.ownerLane != MediaOwnerLane.group ||
        current.mime != attachment.mime ||
        current.mediaType != attachment.mediaType ||
        current.size != attachment.size ||
        current.contentHash != attachment.contentHash ||
        current.encryptionKeyBase64 != attachment.encryptionKeyBase64 ||
        current.encryptionNonce != attachment.encryptionNonce ||
        current.encryptionScheme != attachment.encryptionScheme ||
        current.groupMediaBlobCustodyFingerprint == null ||
        current.groupMediaBlobCustodyFingerprint !=
            attachment.groupMediaBlobCustodyFingerprint) {
      return null;
    }
    return current;
  }

  Future<DirectMediaBlobCustodyRow?> _loadExactIncomingCustody({
    required GroupMediaBlobCustodyRepository repository,
    required MediaAttachment attachment,
    required String groupId,
  }) async {
    final rows = await repository.loadGroupMediaBlobCustodyForMessage(
      groupId: groupId,
      messageId: attachment.messageId,
    );
    final exact = rows.where(
      (row) =>
          row.ownerLane == MediaBlobCustodyOwnerLane.group &&
          row.groupId == groupId &&
          row.messageId == attachment.messageId &&
          row.attachmentId == attachment.id &&
          row.direction == DirectMediaBlobCustodyDirection.incoming &&
          row.recipientPeerId == null,
    );
    if (exact.length != 1) return null;
    final row = exact.single;
    if (row.custodyKind != kGroupMediaBlobCustodyKind ||
        row.contentHash != attachment.contentHash ||
        row.expiresAtMs == null) {
      return null;
    }
    return row;
  }

  Future<MediaAttachment?> _loadDurableLocalAttachment({
    required String messageId,
    required String attachmentId,
  }) async {
    final attachments = await mediaAttachmentRepository
        .getAttachmentsForMessage(messageId, owner: MediaOwnerLane.group);
    for (final candidate in attachments) {
      if (candidate.id != attachmentId ||
          candidate.groupMediaBlobCustodyFingerprint == null ||
          candidate.downloadStatus != kMediaDownloadStatusDone ||
          candidate.localPath == null ||
          candidate.localPath!.isEmpty) {
        continue;
      }
      final absolute = await mediaFileManager.resolveStoredPath(
        candidate.localPath!,
      );
      if (await _isReadablePlaintext(
        File(absolute),
        expectedSize: candidate.size,
      )) {
        return candidate.copyWith(localPath: absolute);
      }
    }
    return null;
  }
}

bool _isExactGroupDownloadReceipt(
  Map<String, dynamic> result,
  DirectMediaBlobCustodyRow expected,
) =>
    result['ok'] == true &&
    result['id'] == expected.custodyBlobId &&
    result['custodyKind'] == expected.custodyKind &&
    result['custodyContract'] == expected.custodyContract &&
    result['contentHash'] == expected.contentHash &&
    result['size'] == expected.ciphertextSize &&
    result['mime'] == expected.transportMime &&
    result['expiresAtMs'] == expected.expiresAtMs &&
    result['custodyRelayPeerId'] is String &&
    (result['custodyRelayPeerId'] as String).trim().isNotEmpty &&
    result['custodyRelayPeerId'] ==
        (result['custodyRelayPeerId'] as String).trim();

bool _isExactGroupAckReceipt(
  Map<String, dynamic> result,
  DirectMediaBlobCustodyRow expected,
) =>
    result['ok'] == true &&
    result['id'] == expected.custodyBlobId &&
    const <String>{'acked', 'already_acked'}.contains(result['ackStatus']) &&
    result['custodyKind'] == expected.custodyKind &&
    result['custodyContract'] == expected.custodyContract &&
    result['contentHash'] == expected.contentHash &&
    result['size'] == expected.ciphertextSize &&
    result['mime'] == expected.transportMime &&
    result['expiresAtMs'] == expected.expiresAtMs &&
    result['custodyRelayPeerId'] == expected.custodyRelayPeerId;

Future<bool> _matchesCiphertext(
  File file,
  DirectMediaBlobCustodyRow expected,
) async {
  if (await FileSystemEntity.type(file.path, followLinks: false) !=
      FileSystemEntityType.file) {
    return false;
  }
  if (await file.length() != expected.ciphertextSize) return false;
  return (await sha256.bind(file.openRead()).first).toString() ==
      expected.contentHash;
}

Future<bool> _isReadablePlaintext(
  File file, {
  required int expectedSize,
}) async {
  if (expectedSize <= 0 ||
      await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.file ||
      await file.length() != expectedSize) {
    return false;
  }
  var readBytes = 0;
  try {
    await for (final chunk in file.openRead()) {
      readBytes += chunk.length;
    }
  } on FileSystemException {
    return false;
  }
  return readBytes == expectedSize;
}

Future<void> _flushFile(File file) async {
  final handle = await file.open(mode: FileMode.append);
  try {
    await handle.flush();
  } finally {
    await handle.close();
  }
}

Future<void> _deleteRegularFile(File file) async {
  try {
    if (await FileSystemEntity.type(file.path, followLinks: false) ==
        FileSystemEntityType.file) {
      await file.delete();
    }
  } on FileSystemException {
    // Retained staging is a bounded orphan; lifecycle cleanup owns it.
  }
}

final class _StrictGroupDownloadInFlight {
  const _StrictGroupDownloadInFlight({
    required this.discriminator,
    required this.future,
  });

  final _StrictGroupDownloadDiscriminator discriminator;
  final Future<MediaAttachment?> future;
}

final class _StrictGroupDownloadScope {
  const _StrictGroupDownloadScope({
    required this.bridge,
    required this.mediaAttachmentRepository,
    required this.mediaFileManager,
    required this.attachmentId,
  });

  final Bridge bridge;
  final MediaAttachmentRepository mediaAttachmentRepository;
  final MediaFileManager mediaFileManager;
  final String attachmentId;

  @override
  bool operator ==(Object other) =>
      other is _StrictGroupDownloadScope &&
      identical(other.bridge, bridge) &&
      identical(other.mediaAttachmentRepository, mediaAttachmentRepository) &&
      identical(other.mediaFileManager, mediaFileManager) &&
      other.attachmentId == attachmentId;

  @override
  int get hashCode => Object.hash(
    identityHashCode(bridge),
    identityHashCode(mediaAttachmentRepository),
    identityHashCode(mediaFileManager),
    attachmentId,
  );
}

final class _StrictGroupDownloadDiscriminator {
  const _StrictGroupDownloadDiscriminator({
    required this.groupId,
    required this.messageId,
    required this.mime,
    required this.plaintextSize,
    required this.contentHash,
    required this.encryptionKeyBase64,
    required this.encryptionNonce,
    required this.encryptionScheme,
    required this.custodyFingerprint,
  });

  final String groupId;
  final String messageId;
  final String mime;
  final int plaintextSize;
  final String? contentHash;
  final String? encryptionKeyBase64;
  final String? encryptionNonce;
  final String? encryptionScheme;
  final String? custodyFingerprint;

  @override
  bool operator ==(Object other) =>
      other is _StrictGroupDownloadDiscriminator &&
      other.groupId == groupId &&
      other.messageId == messageId &&
      other.mime == mime &&
      other.plaintextSize == plaintextSize &&
      other.contentHash == contentHash &&
      other.encryptionKeyBase64 == encryptionKeyBase64 &&
      other.encryptionNonce == encryptionNonce &&
      other.encryptionScheme == encryptionScheme &&
      other.custodyFingerprint == custodyFingerprint;

  @override
  int get hashCode => Object.hash(
    groupId,
    messageId,
    mime,
    plaintextSize,
    contentHash,
    encryptionKeyBase64,
    encryptionNonce,
    encryptionScheme,
    custodyFingerprint,
  );
}
