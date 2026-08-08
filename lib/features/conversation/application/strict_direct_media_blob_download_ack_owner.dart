import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';
import 'package:flutter_app/core/database/direct_media_blob_custody.dart';
import 'package:flutter_app/core/media/direct_media_blob_custody.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart'
    show kMediaDownloadStatusDone;
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';

typedef StrictDirectMediaBlobBeforeSourcePinnedAck =
    FutureOr<void> Function(DirectMediaBlobCustodyRow row);

/// Process-scoped single-flight authority shared by UI-created owners and the
/// bootstrap lifecycle owner.
///
/// Exact requests share one future. A concurrent request for the same durable
/// attachment authority with a different projection fails closed rather than
/// racing another network/decrypt/commit sequence against the same paths.
final class StrictDirectMediaBlobDownloadCoordinator {
  final Map<_StrictDownloadScope, _StrictDownloadInFlight> _inFlight =
      <_StrictDownloadScope, _StrictDownloadInFlight>{};

  Future<MediaAttachment?> run({
    required Bridge bridge,
    required MediaAttachmentRepository mediaAttachmentRepository,
    required MediaFileManager mediaFileManager,
    required MediaAttachment attachment,
    required String contactPeerId,
    required Future<MediaAttachment?> Function() operation,
  }) {
    final scope = _StrictDownloadScope(
      bridge: bridge,
      mediaAttachmentRepository: mediaAttachmentRepository,
      mediaFileManager: mediaFileManager,
      attachmentId: attachment.id,
    );
    final discriminator = _StrictDownloadDiscriminator(
      contactPeerId: contactPeerId,
      messageId: attachment.messageId,
      mime: attachment.mime,
      plaintextSize: attachment.size,
      contentHash: attachment.contentHash,
      encryptionKeyBase64: attachment.encryptionKeyBase64,
      encryptionNonce: attachment.encryptionNonce,
      encryptionScheme: attachment.encryptionScheme,
      commitmentFingerprint: _attachmentCommitmentFingerprint(attachment),
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
    _inFlight[scope] = _StrictDownloadInFlight(
      discriminator: discriminator,
      future: shared,
    );
    return shared;
  }
}

final StrictDirectMediaBlobDownloadCoordinator
_processStrictDirectMediaBlobDownloadCoordinator =
    StrictDirectMediaBlobDownloadCoordinator();

/// Sole feature-layer owner of strict Plan 346 download and source-pinned ACK
/// bridge calls.
///
/// Network transfer happens before the lifecycle lock. The downloaded
/// ciphertext is a unique removable candidate; file promotion and the
/// attachment+v111 commit are then serialized under the repository lifecycle
/// authority. No strict failure falls back to the proof-less media APIs.
final class StrictDirectMediaBlobDownloadAckOwner {
  StrictDirectMediaBlobDownloadAckOwner({
    required this.bridge,
    required this.mediaAttachmentRepository,
    required this.mediaFileManager,
    StrictDirectMediaBlobDownloadCoordinator? downloadCoordinator,
    this.beforeSourcePinnedAck,
    DateTime Function()? now,
  }) : downloadCoordinator =
           downloadCoordinator ??
           _processStrictDirectMediaBlobDownloadCoordinator,
       now = now ?? DateTime.now;

  final Bridge bridge;
  final MediaAttachmentRepository mediaAttachmentRepository;
  final MediaFileManager mediaFileManager;
  final StrictDirectMediaBlobDownloadCoordinator downloadCoordinator;
  final StrictDirectMediaBlobBeforeSourcePinnedAck? beforeSourcePinnedAck;
  final DateTime Function() now;

  DirectMediaBlobCustodyRepository? get _custodyRepository =>
      mediaAttachmentRepository is DirectMediaBlobCustodyRepository
      ? mediaAttachmentRepository as DirectMediaBlobCustodyRepository
      : null;

  IncomingDirectMediaBlobCustodyRepository? get _incomingRepository =>
      mediaAttachmentRepository is IncomingDirectMediaBlobCustodyRepository
      ? mediaAttachmentRepository as IncomingDirectMediaBlobCustodyRepository
      : null;

  Future<MediaAttachment?> downloadAndAcknowledge({
    required MediaAttachment attachment,
    required String contactPeerId,
  }) => downloadCoordinator.run(
    bridge: bridge,
    mediaAttachmentRepository: mediaAttachmentRepository,
    mediaFileManager: mediaFileManager,
    attachment: attachment,
    contactPeerId: contactPeerId,
    operation: () => _downloadAndAcknowledge(
      attachment: attachment,
      contactPeerId: contactPeerId,
    ),
  );

  Future<MediaAttachment?> _downloadAndAcknowledge({
    required MediaAttachment attachment,
    required String contactPeerId,
  }) async {
    final custodyRepository = _custodyRepository;
    final incomingRepository = _incomingRepository;
    if (custodyRepository == null ||
        incomingRepository == null ||
        !custodyRepository.supportsDirectMediaBlobCustody ||
        !incomingRepository.supportsIncomingDirectMediaBlobCustody ||
        attachment.messageId.isEmpty ||
        attachment.ownerLane != MediaOwnerLane.direct ||
        !attachment.hasEncryptionMetadata) {
      return null;
    }
    var custody = await custodyRepository
        .loadDirectMediaBlobCustodyForAttachment(attachment.id);
    if (custody == null ||
        custody.messageId != attachment.messageId ||
        custody.direction != DirectMediaBlobCustodyDirection.incoming ||
        custody.contentHash != attachment.contentHash ||
        !_attachmentMatchesCustodyFingerprint(attachment, custody)) {
      return null;
    }
    final nowMs = now().toUtc().millisecondsSinceEpoch;
    if (custody.expiresAtMs! <= nowMs) {
      await incomingRepository.deleteIncomingDirectMediaBlobIfExpired(
        expected: custody,
        nowMs: nowMs,
      );
      return _loadDurableLocalAttachment(
        messageId: attachment.messageId,
        attachmentId: attachment.id,
      );
    }
    if (custody.state == DirectMediaBlobCustodyState.incomingAckPending) {
      await _acknowledgeReloadedPending(custody);
      return _loadDurableLocalAttachment(
        messageId: attachment.messageId,
        attachmentId: attachment.id,
      );
    }
    if (custody.state != DirectMediaBlobCustodyState.incomingCommitted) {
      return null;
    }
    final alreadyLocal = await _loadDurableLocalAttachment(
      messageId: attachment.messageId,
      attachmentId: attachment.id,
    );
    if (alreadyLocal != null) {
      // Source-less LAN adoption remains incoming_committed until expiry. A
      // lifecycle retry must not turn its durable plaintext into a relay ACK.
      return alreadyLocal;
    }

    final absolutePath = await mediaFileManager.localPathForAttachment(
      contactPeerId: contactPeerId,
      blobId: attachment.id,
      mime: attachment.mime,
    );
    final relativePath = mediaFileManager.relativePathForAttachment(
      contactPeerId: contactPeerId,
      blobId: attachment.id,
      mime: attachment.mime,
    );
    final lanCandidate = File('$absolutePath.enc');
    String? sourceRelayPeerId;
    late File ciphertext;
    var ownsCiphertextCandidate = false;
    if (await _matchesCiphertext(lanCandidate, custody)) {
      // A verified source-less local transfer cannot name a relay. Preserve the
      // incoming_committed row and converge by its persisted expiry.
      ciphertext = lanCandidate;
    } else {
      final relayCandidate = File(
        '$absolutePath.strict-${now().toUtc().microsecondsSinceEpoch}.enc',
      );
      await relayCandidate.parent.create(recursive: true);
      final result = await callP2PMediaDownload(
        bridge,
        id: attachment.id,
        outputPath: relayCandidate.path,
        custodyKind: custody.custodyKind,
        custodyContract: custody.custodyContract,
        contentHash: custody.contentHash,
        size: custody.ciphertextSize,
        mime: custody.transportMime,
        expiresAtMs: custody.expiresAtMs,
        payloadSizeBytes: custody.ciphertextSize,
      );
      if (!_isExactDownloadReceipt(result, custody) ||
          !await _matchesCiphertext(relayCandidate, custody)) {
        await _deleteRegularFile(relayCandidate);
        return null;
      }
      sourceRelayPeerId = result['custodyRelayPeerId'] as String;
      ciphertext = relayCandidate;
      ownsCiphertextCandidate = true;
    }

    try {
      final committed = await custodyRepository
          .runDirectMediaBlobCustodyLifecycle(() async {
            final current = await custodyRepository
                .loadDirectMediaBlobCustodyForAttachment(attachment.id);
            if (current == null ||
                !current.exactDatabaseProjectionMatches(custody!)) {
              return false;
            }
            final decryptedPath = await callBlobDecrypt(
              bridge,
              filePath: ciphertext.path,
              keyBase64: attachment.encryptionKeyBase64!,
              nonce: attachment.encryptionNonce!,
            );
            final decrypted = File(decryptedPath);
            if (!await decrypted.exists() ||
                await decrypted.length() != attachment.size) {
              await _deleteRegularFile(decrypted);
              return false;
            }
            final canonical = File(absolutePath);
            await canonical.parent.create(recursive: true);
            if (decrypted.path != canonical.path) {
              await _deleteRegularFile(canonical);
              await decrypted.rename(canonical.path);
            }
            await _flushFile(canonical);
            final didCommit = await incomingRepository
                .commitIncomingDirectMediaBlobLocalPath(
                  expectedAttachment: attachment,
                  expectedCustody: custody,
                  localPath: relativePath,
                  sourceRelayPeerId: sourceRelayPeerId,
                  updatedAt: now().toUtc().toIso8601String(),
                );
            if (!didCommit) return false;
            if (ownsCiphertextCandidate ||
                identical(ciphertext, lanCandidate)) {
              await _deleteRegularFile(ciphertext);
            }
            return true;
          });
      if (!committed) return null;
    } finally {
      if (ownsCiphertextCandidate) await _deleteRegularFile(ciphertext);
    }

    if (sourceRelayPeerId != null) {
      custody = await custodyRepository.loadDirectMediaBlobCustodyForAttachment(
        attachment.id,
      );
      if (custody != null &&
          custody.state == DirectMediaBlobCustodyState.incomingAckPending) {
        await _acknowledgeReloadedPending(custody);
      }
    }
    return _loadDurableLocalAttachment(
      messageId: attachment.messageId,
      attachmentId: attachment.id,
    );
  }

  /// Retries one already-durable ACK obligation against only its persisted
  /// source relay. Success and `already_acked` both converge by exact row
  /// deletion; every failure retains the row with bounded retry metadata.
  Future<bool> acknowledgePending(DirectMediaBlobCustodyRow expected) async {
    final custodyRepository = _custodyRepository;
    final incomingRepository = _incomingRepository;
    if (custodyRepository == null ||
        incomingRepository == null ||
        expected.state != DirectMediaBlobCustodyState.incomingAckPending ||
        expected.custodyRelayPeerId == null) {
      return false;
    }
    try {
      final result = await callP2PMediaDelete(
        bridge,
        id: expected.attachmentId,
        custodyKind: expected.custodyKind,
        custodyContract: expected.custodyContract,
        contentHash: expected.contentHash,
        size: expected.ciphertextSize,
        mime: expected.transportMime,
        expiresAtMs: expected.expiresAtMs,
        custodyRelayPeerId: expected.custodyRelayPeerId,
      );
      if (_isExactAckReceipt(result, expected)) {
        return incomingRepository.deleteIncomingDirectMediaBlobAckIfExact(
          expected,
        );
      }
    } on Object {
      // Persist the retry projection below; no proof-less/fan-out fallback.
    }

    final attemptAt = now().toUtc();
    final retryCount = expected.retryCount + 1;
    final exponent = math.min(retryCount, 8);
    final delaySeconds = math.min(300, 1 << exponent);
    final retry = expected.copyWith(
      retryCount: retryCount,
      lastAttemptAt: attemptAt.toIso8601String(),
      nextAttemptAt: attemptAt
          .add(Duration(seconds: delaySeconds))
          .toIso8601String(),
      updatedAt: attemptAt.toIso8601String(),
    );
    await custodyRepository.transitionDirectMediaBlobCustodyIfExact(
      expected: expected,
      next: retry,
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

  Future<MediaAttachment?> _loadDurableLocalAttachment({
    required String messageId,
    required String attachmentId,
  }) async {
    final attachments = await mediaAttachmentRepository
        .getAttachmentsForMessage(messageId, owner: MediaOwnerLane.direct);
    for (final candidate in attachments) {
      if (candidate.id != attachmentId ||
          candidate.downloadStatus != kMediaDownloadStatusDone ||
          candidate.localPath == null ||
          candidate.localPath!.isEmpty) {
        continue;
      }
      final absolute = await mediaFileManager.resolveStoredPath(
        candidate.localPath!,
      );
      if (await File(absolute).exists()) {
        return candidate.copyWith(localPath: absolute);
      }
    }
    return null;
  }
}

bool _isExactDownloadReceipt(
  Map<String, dynamic> result,
  DirectMediaBlobCustodyRow expected,
) =>
    result['ok'] == true &&
    result['id'] == expected.attachmentId &&
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

bool _isExactAckReceipt(
  Map<String, dynamic> result,
  DirectMediaBlobCustodyRow expected,
) =>
    result['ok'] == true &&
    result['id'] == expected.attachmentId &&
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
    // A retained candidate is a bounded orphan; lifecycle cleanup owns it.
  }
}

final class _StrictDownloadInFlight {
  const _StrictDownloadInFlight({
    required this.discriminator,
    required this.future,
  });

  final _StrictDownloadDiscriminator discriminator;
  final Future<MediaAttachment?> future;
}

final class _StrictDownloadScope {
  const _StrictDownloadScope({
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
      other is _StrictDownloadScope &&
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

final class _StrictDownloadDiscriminator {
  const _StrictDownloadDiscriminator({
    required this.contactPeerId,
    required this.messageId,
    required this.mime,
    required this.plaintextSize,
    required this.contentHash,
    required this.encryptionKeyBase64,
    required this.encryptionNonce,
    required this.encryptionScheme,
    required this.commitmentFingerprint,
  });

  final String contactPeerId;
  final String messageId;
  final String mime;
  final int plaintextSize;
  final String? contentHash;
  final String? encryptionKeyBase64;
  final String? encryptionNonce;
  final String? encryptionScheme;
  final String? commitmentFingerprint;

  @override
  bool operator ==(Object other) =>
      other is _StrictDownloadDiscriminator &&
      other.contactPeerId == contactPeerId &&
      other.messageId == messageId &&
      other.mime == mime &&
      other.plaintextSize == plaintextSize &&
      other.contentHash == contentHash &&
      other.encryptionKeyBase64 == encryptionKeyBase64 &&
      other.encryptionNonce == encryptionNonce &&
      other.encryptionScheme == encryptionScheme &&
      other.commitmentFingerprint == commitmentFingerprint;

  @override
  int get hashCode => Object.hash(
    contactPeerId,
    messageId,
    mime,
    plaintextSize,
    contentHash,
    encryptionKeyBase64,
    encryptionNonce,
    encryptionScheme,
    commitmentFingerprint,
  );
}

String? _attachmentCommitmentFingerprint(MediaAttachment attachment) {
  final persisted = attachment.directMediaBlobCustodyFingerprint;
  if (persisted != null) return persisted;
  final commitment = attachment.blobCustody;
  if (commitment == null || !commitment.isValid) return null;
  try {
    return computeDirectMediaBlobCommitmentFingerprint(
      attachmentId: attachment.id,
      commitment: commitment,
    );
  } on FormatException {
    return null;
  }
}

bool _attachmentMatchesCustodyFingerprint(
  MediaAttachment attachment,
  DirectMediaBlobCustodyRow custody,
) {
  final expiresAtMs = custody.expiresAtMs;
  if (expiresAtMs == null) return false;
  final expected = computeDirectMediaBlobCommitmentFingerprint(
    attachmentId: custody.attachmentId,
    commitment: DirectMediaBlobCustodyCommitment(
      kind: custody.custodyKind,
      contract: custody.custodyContract,
      contentHash: custody.contentHash,
      ciphertextSize: custody.ciphertextSize,
      transportMime: custody.transportMime,
      expiresAtMs: expiresAtMs,
    ),
  );
  final persisted = attachment.directMediaBlobCustodyFingerprint;
  if (persisted != null && persisted != expected) return false;
  final wire = attachment.blobCustody;
  if (wire == null) return true;
  try {
    return computeDirectMediaBlobCommitmentFingerprint(
          attachmentId: attachment.id,
          commitment: wire,
        ) ==
        expected;
  } on FormatException {
    return false;
  }
}
