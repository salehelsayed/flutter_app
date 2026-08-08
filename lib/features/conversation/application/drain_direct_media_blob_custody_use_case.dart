import 'package:flutter_app/core/database/direct_media_blob_custody.dart';
import 'package:flutter_app/core/media/direct_media_blob_artifact_store.dart';
import 'package:flutter_app/core/media/direct_media_blob_terminalization.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';

import 'strict_direct_media_blob_download_ack_owner.dart';

typedef RetryIncomingDirectMediaBlob =
    Future<bool> Function(DirectMediaBlobCustodyRow row);

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
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  final DirectMediaBlobCustodyRepository repository;
  final IncomingDirectMediaBlobCustodyRepository incomingRepository;
  final DirectMediaBlobArtifactStore artifactStore;
  final Future<String?> Function() identityPeerId;
  final StrictDirectMediaBlobDownloadAckOwner strictDownloadAckOwner;
  final RetryIncomingDirectMediaBlob? retryIncomingDownload;
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
            if (path == null ||
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
}
