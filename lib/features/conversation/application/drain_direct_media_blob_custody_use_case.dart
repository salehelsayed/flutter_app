import 'package:flutter_app/core/database/direct_media_blob_custody.dart';
import 'package:flutter_app/core/database/helpers/direct_media_blob_custody_db_helpers.dart'
    show DirectMediaBlobCustodyNaturalKey;
import 'package:flutter_app/core/media/direct_media_blob_artifact_store.dart';
import 'package:flutter_app/core/media/direct_media_blob_terminalization.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';

import 'strict_direct_media_blob_download_ack_owner.dart';

typedef RetryIncomingDirectMediaBlob =
    Future<bool> Function(DirectMediaBlobCustodyRow row);
typedef RetryOutgoingLinkedDirectMediaBlobMessage =
    Future<bool> Function(String messageId);

/// Whether the automatic v111 drain may complete one incoming parent's
/// transfer over the network.
///
/// A tombstoned or hidden parent keeps its independent obligation (ACK or
/// expiry still converge) but its plaintext must never be re-downloaded after
/// the user's deletion won. A redacted Protected/View-Once parent is likewise
/// RETAINED without network: its plaintext requires explicit user intent
/// through `downloadMedia`, which this drain deliberately bypasses.
///
/// Production and its proof call this one predicate; neither copies its body.
bool directMediaBlobDrainMayDownloadIncomingParent(
  ConversationMessage? parent,
) =>
    parent != null &&
    parent.isIncoming &&
    !parent.isDeleted &&
    parent.hiddenAt == null &&
    !parent.privateMediaPolicy.requiresRedaction;

final class DirectMediaBlobCustodyDrainResult {
  const DirectMediaBlobCustodyDrainResult({
    required this.completed,
    required this.retained,
    required this.failed,
  });

  final int completed;
  final int retained;
  final int failed;
}

/// Bounded startup/resume convergence for independent v111 authority.
final class DirectMediaBlobCustodyDrain {
  DirectMediaBlobCustodyDrain({
    required this.repository,
    required this.incomingRepository,
    required this.artifactStore,
    required this.identityPeerId,
    required this.strictDownloadAckOwner,
    this.retryIncomingDownload,
    this.retryOutgoingLinkedMessage,
    this.countOtherArtifactReferences,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  final DirectMediaBlobCustodyRepository repository;
  final IncomingDirectMediaBlobCustodyRepository incomingRepository;
  final DirectMediaBlobArtifactStore artifactStore;
  final Future<String?> Function() identityPeerId;
  final StrictDirectMediaBlobDownloadAckOwner strictDownloadAckOwner;
  final RetryIncomingDirectMediaBlob? retryIncomingDownload;
  final RetryOutgoingLinkedDirectMediaBlobMessage? retryOutgoingLinkedMessage;

  /// 362 (v114): counts sibling rows still referencing the exact shared
  /// `(path, contentHash, ciphertextSize)` artifact, excluding one natural
  /// row. When injected, cleanup unlinks the file only with the LAST
  /// reference while still retiring each exact row; when absent, incumbent
  /// single-target behavior (always unlink first) is preserved.
  final Future<int> Function({
    required String ciphertextRelativePath,
    required String contentHash,
    required int ciphertextSize,
    required DirectMediaBlobCustodyNaturalKey excluding,
  })?
  countOtherArtifactReferences;

  final DateTime Function() now;

  /// Local-only cleanup runs before account-migration network gating.
  Future<DirectMediaBlobCustodyDrainResult> runLocalCleanupBounded({
    int limit = 50,
  }) async {
    if (limit <= 0) {
      return const DirectMediaBlobCustodyDrainResult(
        completed: 0,
        retained: 0,
        failed: 0,
      );
    }
    var completed = 0;
    var retained = 0;
    var failed = 0;
    final identity = await identityPeerId();
    if (identity == null || identity.trim().isEmpty) {
      return const DirectMediaBlobCustodyDrainResult(
        completed: 0,
        retained: 0,
        failed: 1,
      );
    }
    final terminalizationRepository =
        repository is OutgoingDirectMediaBlobTerminalizationRepository
        ? repository as OutgoingDirectMediaBlobTerminalizationRepository
        : null;
    if (terminalizationRepository != null &&
        terminalizationRepository
            .supportsOutgoingDirectMediaBlobTerminalization) {
      final activeRows = await repository.loadDirectMediaBlobCustodyByStates(
        const <DirectMediaBlobCustodyState>{
          DirectMediaBlobCustodyState.outgoingPrepared,
          DirectMediaBlobCustodyState.outgoingStored,
        },
        limit: limit,
      );
      final messageIds = activeRows.map((row) => row.messageId).toSet();
      final nowMs = now().toUtc().millisecondsSinceEpoch;
      for (final messageId in messageIds) {
        try {
          final completeRows = await repository
              .loadDirectMediaBlobCustodyForMessage(messageId);
          final outgoingRows = completeRows
              .where(
                (row) =>
                    row.direction == DirectMediaBlobCustodyDirection.outgoing,
              )
              .toList(growable: false);
          if (outgoingRows.isEmpty) continue;
          var outcome = await terminalizationRepository
              .terminalizeOutgoingDirectMediaBlobGenerationIfExact(
                expectedRows: outgoingRows,
                reason:
                    DirectMediaBlobTerminalizationReason.parentDeletedOrMissing,
                nowMs: nowMs,
              );
          if (outcome == DirectMediaBlobTerminalizationOutcome.refused) {
            outcome = await terminalizationRepository
                .terminalizeOutgoingDirectMediaBlobGenerationIfExact(
                  expectedRows: outgoingRows,
                  reason:
                      DirectMediaBlobTerminalizationReason.expiredUnboundProof,
                  nowMs: nowMs,
                );
          }
          if (!outcome.publishedCleanupAuthority) {
            retained += outgoingRows.length;
          }
        } on Object {
          failed++;
        }
      }
    }
    final cleanupRows = await repository.loadDirectMediaBlobCustodyByStates(
      const <DirectMediaBlobCustodyState>{
        DirectMediaBlobCustodyState.outgoingCleanupPending,
      },
      limit: limit,
    );
    for (final row in cleanupRows) {
      try {
        final removed = await repository.runDirectMediaBlobCustodyLifecycle(
          () async {
            final path = row.ciphertextRelativePath;
            if (path == null) return false;
            // v114: sibling target rows may share this exact artifact. Skip
            // the file unlink while another reference survives — the exact
            // row still retires and the LAST sibling unlinks the file.
            final countOthers = countOtherArtifactReferences;
            var unlinkArtifact = true;
            if (countOthers != null) {
              unlinkArtifact =
                  await countOthers(
                    ciphertextRelativePath: path,
                    contentHash: row.contentHash,
                    ciphertextSize: row.ciphertextSize,
                    excluding: DirectMediaBlobCustodyNaturalKey.ofRow(row),
                  ) ==
                  0;
            }
            if (unlinkArtifact &&
                !await artifactStore.deleteOwnedArtifact(
                  identityPeerId: identity,
                  relativePath: path,
                )) {
              return false;
            }
            return repository.deleteDirectMediaBlobCleanupPendingIfExact(row);
          },
        );
        if (removed) {
          completed++;
        } else {
          retained++;
        }
      } on Object {
        failed++;
      }
    }

    try {
      await repository.runDirectMediaBlobCustodyLifecycle(() async {
        final liveOutgoing = await repository
            .loadDirectMediaBlobCustodyByStates(
              const <DirectMediaBlobCustodyState>{
                DirectMediaBlobCustodyState.outgoingPrepared,
                DirectMediaBlobCustodyState.outgoingStored,
                DirectMediaBlobCustodyState.outgoingCleanupPending,
              },
              limit: 50,
            );
        if (liveOutgoing.length == 50) {
          // The loader is deliberately bounded. Without a complete authority
          // inventory, absence is not proven and orphan deletion must wait.
          retained++;
          return;
        }
        final referenced = liveOutgoing
            .map((row) => row.ciphertextRelativePath)
            .whereType<String>()
            .toSet();
        final orphans = await artifactStore.cleanupUnreferencedArtifacts(
          identityPeerId: identity,
          referencedRelativePaths: referenced,
          limit: 50,
        );
        completed += orphans.deleted;
        retained += orphans.retained;
      });
    } on Object {
      failed++;
    }
    return DirectMediaBlobCustodyDrainResult(
      completed: completed,
      retained: retained,
      failed: failed,
    );
  }

  /// Network-capable recovery runs after bridge health and before mutable
  /// upload retry. ACK rows are source-pinned; source-less LAN rows are never
  /// deleted early and converge only at their exact persisted expiry.
  Future<DirectMediaBlobCustodyDrainResult> runNetworkBounded({
    int limit = 50,
  }) async {
    final rows = await repository
        .loadDirectMediaBlobCustodyByStates(const <DirectMediaBlobCustodyState>{
          DirectMediaBlobCustodyState.incomingCommitted,
          DirectMediaBlobCustodyState.incomingAckPending,
        }, limit: limit);
    return _convergeIncomingRows(rows);
  }

  /// The exact per-row incoming convergence both network-bounded entry points
  /// share, so the linked runtime cannot drift from the primary's semantics.
  Future<DirectMediaBlobCustodyDrainResult> _convergeIncomingRows(
    List<DirectMediaBlobCustodyRow> rows,
  ) async {
    var completed = 0;
    var retained = 0;
    var failed = 0;
    final nowUtc = now().toUtc();
    final nowMs = nowUtc.millisecondsSinceEpoch;
    for (final row in rows) {
      try {
        if (row.expiresAtMs! <= nowMs) {
          final removed = await incomingRepository
              .deleteIncomingDirectMediaBlobIfExpired(
                expected: row,
                nowMs: nowMs,
              );
          removed ? completed++ : retained++;
          continue;
        }
        if (row.state == DirectMediaBlobCustodyState.incomingAckPending) {
          final nextAttempt = row.nextAttemptAt == null
              ? null
              : DateTime.tryParse(row.nextAttemptAt!)?.toUtc();
          if (nextAttempt != null && nextAttempt.isAfter(nowUtc)) {
            retained++;
            continue;
          }
          final acknowledged = await strictDownloadAckOwner.acknowledgePending(
            row,
          );
          acknowledged ? completed++ : retained++;
          continue;
        }
        final retry = retryIncomingDownload;
        if (retry == null) {
          retained++;
        } else if (await retry(row)) {
          completed++;
        } else {
          retained++;
        }
      } on Object {
        failed++;
      }
    }
    return DirectMediaBlobCustodyDrainResult(
      completed: completed,
      retained: retained,
      failed: failed,
    );
  }

  Future<DirectMediaBlobCustodyDrainResult> _cleanupExactOutgoingRows(
    Iterable<DirectMediaBlobCustodyRow> candidates,
  ) async {
    final rowsByKey =
        <DirectMediaBlobCustodyNaturalKey, DirectMediaBlobCustodyRow>{
          for (final row in candidates)
            DirectMediaBlobCustodyNaturalKey.ofRow(row): row,
        };
    if (rowsByKey.isEmpty) {
      return const DirectMediaBlobCustodyDrainResult(
        completed: 0,
        retained: 0,
        failed: 0,
      );
    }
    final identity = await identityPeerId();
    if (identity == null || identity.trim().isEmpty) {
      return const DirectMediaBlobCustodyDrainResult(
        completed: 0,
        retained: 0,
        failed: 1,
      );
    }
    var completed = 0;
    var retained = 0;
    var failed = 0;
    for (final row in rowsByKey.values) {
      try {
        final removed = await repository.runDirectMediaBlobCustodyLifecycle(
          () async {
            final path = row.ciphertextRelativePath;
            if (path == null) return false;
            final countOthers = countOtherArtifactReferences;
            final unlinkArtifact =
                countOthers == null ||
                await countOthers(
                      ciphertextRelativePath: path,
                      contentHash: row.contentHash,
                      ciphertextSize: row.ciphertextSize,
                      excluding: DirectMediaBlobCustodyNaturalKey.ofRow(row),
                    ) ==
                    0;
            if (unlinkArtifact &&
                !await artifactStore.deleteOwnedArtifact(
                  identityPeerId: identity,
                  relativePath: path,
                )) {
              return false;
            }
            return repository.deleteDirectMediaBlobCleanupPendingIfExact(row);
          },
        );
        removed ? completed++ : retained++;
      } on Object {
        failed++;
      }
    }
    return DirectMediaBlobCustodyDrainResult(
      completed: completed,
      retained: retained,
      failed: failed,
    );
  }

  /// 362: the restricted linked runtime's converger.
  ///
  /// Same per-row work as [runNetworkBounded], but the page comes from the
  /// LINKED-scoped loader so a linked secondary never converges rows it does
  /// not own. It is one more entry point on the SINGLE shared v111 lifecycle
  /// owner rather than a second drain instance, because the bootstrap phase
  /// contract freezes `DirectMediaBlobCustodyDrain(` to exactly one
  /// construction.
  ///
  /// Fails closed: a repository without the linked scope drains NOTHING here
  /// rather than falling back to the unrestricted page.
  ///
  /// Deliberately does not touch local cleanup. `runLocalCleanupBounded`'s
  /// orphan sweep builds its referenced-path set from a GLOBAL live-outgoing
  /// inventory, so running it against a linked-only page would classify
  /// primary-authored ciphertext as unreferenced and delete it.
  Future<DirectMediaBlobCustodyDrainResult> runNetworkBoundedLinked({
    int limit = 50,
  }) async {
    final candidate = repository;
    if (candidate is! LinkedDirectMediaBlobCustodyDrainRepository) {
      return const DirectMediaBlobCustodyDrainResult(
        completed: 0,
        retained: 0,
        failed: 0,
      );
    }
    final linkedRepository =
        candidate as LinkedDirectMediaBlobCustodyDrainRepository;
    if (!linkedRepository.supportsLinkedDirectMediaBlobCustodyDrain) {
      return const DirectMediaBlobCustodyDrainResult(
        completed: 0,
        retained: 0,
        failed: 0,
      );
    }
    // Separate bounded pages prevent a full incoming page from starving
    // outgoing survivors (or cleanup) forever.
    final incomingRows = await linkedRepository
        .loadLinkedDirectMediaBlobCustodyByStates(
          const <DirectMediaBlobCustodyState>{
            DirectMediaBlobCustodyState.incomingCommitted,
            DirectMediaBlobCustodyState.incomingAckPending,
          },
          limit: limit,
        );
    final activeOutgoingRows = await linkedRepository
        .loadLinkedDirectMediaBlobCustodyByStates(
          const <DirectMediaBlobCustodyState>{
            DirectMediaBlobCustodyState.outgoingPrepared,
            DirectMediaBlobCustodyState.outgoingStored,
          },
          limit: limit,
        );
    final initialCleanupRows = await linkedRepository
        .loadLinkedDirectMediaBlobCustodyByStates(
          const <DirectMediaBlobCustodyState>{
            DirectMediaBlobCustodyState.outgoingCleanupPending,
          },
          limit: limit,
        );

    var completed = 0;
    var retained = 0;
    var failed = 0;
    final terminalizationRepository =
        repository is OutgoingDirectMediaBlobTerminalizationRepository
        ? repository as OutgoingDirectMediaBlobTerminalizationRepository
        : null;
    final messageIds = activeOutgoingRows.map((row) => row.messageId).toSet();
    final nowMs = now().toUtc().millisecondsSinceEpoch;
    for (final messageId in messageIds) {
      try {
        final completeRows = await repository
            .loadDirectMediaBlobCustodyForMessage(messageId);
        final outgoingRows = completeRows
            .where(
              (row) =>
                  row.direction == DirectMediaBlobCustodyDirection.outgoing,
            )
            .toList(growable: false);
        if (outgoingRows.isEmpty ||
            outgoingRows.any((row) => !row.isLinkedFanoutRow)) {
          retained++;
          continue;
        }

        var terminalized = false;
        if (terminalizationRepository != null &&
            terminalizationRepository
                .supportsOutgoingDirectMediaBlobTerminalization) {
          var outcome = await terminalizationRepository
              .terminalizeOutgoingDirectMediaBlobGenerationIfExact(
                expectedRows: outgoingRows,
                reason:
                    DirectMediaBlobTerminalizationReason.parentDeletedOrMissing,
                nowMs: nowMs,
              );
          if (outcome == DirectMediaBlobTerminalizationOutcome.refused) {
            outcome = await terminalizationRepository
                .terminalizeOutgoingDirectMediaBlobGenerationIfExact(
                  expectedRows: outgoingRows,
                  reason:
                      DirectMediaBlobTerminalizationReason.expiredUnboundProof,
                  nowMs: nowMs,
                );
          }
          terminalized = outcome.publishedCleanupAuthority;
        }
        if (terminalized) continue;

        final retry = retryOutgoingLinkedMessage;
        if (retry == null) {
          retained++;
        } else if (await retry(messageId)) {
          completed++;
        } else {
          retained++;
        }
      } on Object {
        failed++;
      }
    }

    // Terminalization above may have published new cleanup rows. Reload the
    // scoped page and merge it with the initial page by natural identity.
    final refreshedCleanupRows = await linkedRepository
        .loadLinkedDirectMediaBlobCustodyByStates(
          const <DirectMediaBlobCustodyState>{
            DirectMediaBlobCustodyState.outgoingCleanupPending,
          },
          limit: limit,
        );
    final cleanup = await _cleanupExactOutgoingRows(<DirectMediaBlobCustodyRow>[
      ...initialCleanupRows,
      ...refreshedCleanupRows,
    ]);
    final incoming = await _convergeIncomingRows(incomingRows);
    return DirectMediaBlobCustodyDrainResult(
      completed: completed + cleanup.completed + incoming.completed,
      retained: retained + cleanup.retained + incoming.retained,
      failed: failed + cleanup.failed + incoming.failed,
    );
  }
}
