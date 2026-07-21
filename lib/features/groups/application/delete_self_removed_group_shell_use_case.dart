import 'dart:async';

import 'package:flutter_app/core/database/helpers/group_media_deletion_journal_db_helpers.dart';
import 'package:flutter_app/features/groups/application/group_membership_event_watermark.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

const int kSelfRemovedShellMediaPrepareLimit = 100;

enum DeleteSelfRemovedGroupShellResult {
  deleted,
  alreadyAbsent,
  refusedStateChanged,
  cleanupIncomplete,
}

typedef DeleteSelfRemovedGroupShellCallback =
    Future<DeleteSelfRemovedGroupShellResult> Function({
      required String groupId,
      required String selfPeerId,
    });

/// Process-wide production seam. Tests normally inject an explicit callback;
/// absence fails closed and must never fall through to voluntary leave.
DeleteSelfRemovedGroupShellCallback? defaultDeleteSelfRemovedGroupShell;

typedef SelfRemovedShellMediaPrepare =
    Future<GroupMediaDeletePrepareResult> Function({
      required String groupId,
      required String messageId,
      required String operationId,
    });

typedef SelfRemovedShellAvatarPathSnapshot =
    Future<String?> Function(String groupId);

typedef SelfRemovedShellAvatarDelete = Future<void> Function(String path);

/// Bridge-free local cleanup orchestration. Persistence and secure-store
/// ordering are owned by [SelfRemovedGroupShellRepository]; this layer bounds
/// canonical media preparation and holds the membership phase across the
/// destructive authority transition.
class DeleteSelfRemovedGroupShellUseCase {
  DeleteSelfRemovedGroupShellUseCase({
    required this.repository,
    required this.prepareMedia,
    required this.runMediaReconciler,
    required this.operationIdFactory,
    required this.snapshotAvatarPath,
    required this.deleteAvatar,
    this.mediaPrepareLimit = kSelfRemovedShellMediaPrepareLimit,
  }) : assert(mediaPrepareLimit > 0);

  final SelfRemovedGroupShellRepository repository;
  final SelfRemovedShellMediaPrepare prepareMedia;
  final Future<void> Function() runMediaReconciler;
  final String Function() operationIdFactory;
  final SelfRemovedShellAvatarPathSnapshot snapshotAvatarPath;
  final SelfRemovedShellAvatarDelete deleteAvatar;
  final int mediaPrepareLimit;

  Future<DeleteSelfRemovedGroupShellResult> call({
    required String groupId,
    required String selfPeerId,
  }) async {
    var dispatchReconciler = false;
    final result = await runGroupMembershipMutationLocked(
      groupId: groupId,
      action: () async {
        final SelfRemovedShellAuthoritySnapshot authority;
        try {
          authority = await repository.loadSelfRemovedShellAuthority(
            groupId: groupId,
            selfPeerId: selfPeerId,
          );
        } catch (_) {
          return DeleteSelfRemovedGroupShellResult.cleanupIncomplete;
        }
        if (authority.shape == SelfRemovedShellAuthorityShape.absent) {
          final SelfRemovedShellFreshnessFloor? floor;
          try {
            floor = await repository.loadSelfRemovedShellFreshnessFloor(
              groupId,
            );
          } catch (_) {
            return DeleteSelfRemovedGroupShellResult.cleanupIncomplete;
          }
          return floor != null &&
                  floor.groupId == groupId &&
                  floor.selfPeerId == selfPeerId
              ? DeleteSelfRemovedGroupShellResult.alreadyAbsent
              : DeleteSelfRemovedGroupShellResult.refusedStateChanged;
        }
        if (authority.shape !=
            SelfRemovedShellAuthorityShape.markedSelfAbsent) {
          return DeleteSelfRemovedGroupShellResult.refusedStateChanged;
        }
        final marker = authority.selfRemovedAt?.toUtc();
        if (marker == null ||
            (authority.lastMembershipEventAt?.toUtc().isAfter(marker) ??
                false)) {
          return DeleteSelfRemovedGroupShellResult.refusedStateChanged;
        }

        // Snapshot the old membership instance's canonical cache address while
        // the marker is still present. The media-authority load immediately
        // below is the required post-snapshot predicate re-read.
        final String? avatarPath;
        try {
          avatarPath = await snapshotAvatarPath(groupId);
        } catch (_) {
          return DeleteSelfRemovedGroupShellResult.cleanupIncomplete;
        }

        final SelfRemovedShellMediaBatch media;
        try {
          media = await repository.loadSelfRemovedShellMediaParents(
            expected: authority,
            limit: mediaPrepareLimit,
          );
        } catch (_) {
          dispatchReconciler = true;
          return DeleteSelfRemovedGroupShellResult.cleanupIncomplete;
        }
        if (media.outcome != SelfRemovedShellMutationOutcome.committed) {
          return media.outcome ==
                  SelfRemovedShellMutationOutcome.refusedStateChanged
              ? DeleteSelfRemovedGroupShellResult.refusedStateChanged
              : DeleteSelfRemovedGroupShellResult.cleanupIncomplete;
        }

        for (final parent in media.parents) {
          try {
            final prepared = await prepareMedia(
              groupId: groupId,
              messageId: parent.messageId,
              operationId: operationIdFactory(),
            );
            switch (prepared.outcome) {
              case GroupMediaDeletePrepareOutcome.prepared:
              case GroupMediaDeletePrepareOutcome.alreadyDeleted:
                // Either outcome can leave an existing durable media journal.
                // Every later return must therefore dispatch reconciliation
                // after the membership phase is released.
                dispatchReconciler = true;
                break;
              case GroupMediaDeletePrepareOutcome.parentMissing:
              case GroupMediaDeletePrepareOutcome.conflictingTombstone:
                dispatchReconciler = true;
                return DeleteSelfRemovedGroupShellResult.cleanupIncomplete;
            }
          } catch (_) {
            dispatchReconciler = true;
            return DeleteSelfRemovedGroupShellResult.cleanupIncomplete;
          }
        }
        if (media.hasOverflow) {
          dispatchReconciler = true;
          return DeleteSelfRemovedGroupShellResult.cleanupIncomplete;
        }

        try {
          final terminal = await repository.terminalizeSelfRemovedShell(
            expected: authority,
          );
          if (terminal != SelfRemovedShellMutationOutcome.committed) {
            return terminal ==
                    SelfRemovedShellMutationOutcome.refusedStateChanged
                ? DeleteSelfRemovedGroupShellResult.refusedStateChanged
                : DeleteSelfRemovedGroupShellResult.cleanupIncomplete;
          }

          final floor = await repository.appendSelfRemovedShellFreshnessFloor(
            expected: authority,
          );
          final purge = await repository.purgeSelfRemovedShell(
            expected: authority,
            floor: floor,
            deletedAt: DateTime.now().toUtc(),
          );
          if (purge == SelfRemovedShellMutationOutcome.committed) {
            // Avatar cleanup is intentionally best-effort after group-last and
            // before releasing the membership phase. A same-id accepted
            // re-entry therefore cannot install a new avatar between the SQL
            // delete and this old-cache delete.
            if (avatarPath != null && avatarPath.trim().isNotEmpty) {
              try {
                await deleteAvatar(avatarPath);
              } catch (_) {}
            }
            dispatchReconciler = true;
            return DeleteSelfRemovedGroupShellResult.deleted;
          }
          return purge == SelfRemovedShellMutationOutcome.refusedStateChanged
              ? DeleteSelfRemovedGroupShellResult.refusedStateChanged
              : DeleteSelfRemovedGroupShellResult.cleanupIncomplete;
        } on SelfRemovedShellStateChangedException {
          return DeleteSelfRemovedGroupShellResult.refusedStateChanged;
        } catch (_) {
          return DeleteSelfRemovedGroupShellResult.cleanupIncomplete;
        }
      },
    );

    // Journal reconciliation owns post-commit media files/attachment keys. It
    // must never extend the authority lock or turn a committed delete into a
    // false failure.
    if (dispatchReconciler) {
      unawaited(
        Future<void>.sync(runMediaReconciler).catchError((Object _) {}),
      );
    }
    return result;
  }
}
