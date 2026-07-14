import 'package:flutter_app/features/groups/application/group_media_batch_forward.dart';
import 'package:flutter_app/features/groups/application/announcement_media_forward_request.dart';
import 'package:flutter_app/features/groups/application/group_media_forward_intent.dart';
import 'package:flutter_app/features/groups/application/group_shared_media_library_controller.dart';

import 'share_batch_delivery_coordinator.dart';
import 'share_target_selection.dart';

enum GroupMediaBatchForwardCellStatus { sent, queued, failed }

enum GroupMediaBatchForwardAttemptDenial { invalidRequest, sourceUnavailable }

enum GroupMediaBatchForwardProgressPhase { uploading, sending }

enum GroupMediaBatchForwardLibraryLaunchStatus { cancelled, denied, completed }

class GroupMediaBatchForwardCellKey {
  GroupMediaBatchForwardCellKey({
    required this.sourceIdentity,
    required this.targetKey,
  }) {
    if (sourceIdentity.groupId.trim().isEmpty ||
        sourceIdentity.messageId.trim().isEmpty ||
        sourceIdentity.attachmentId.trim().isEmpty) {
      throw ArgumentError('sourceIdentity must be complete');
    }
    if (targetKey.trim().isEmpty) {
      throw ArgumentError('targetKey must be nonblank');
    }
  }

  final GroupSharedMediaIdentity sourceIdentity;
  final String targetKey;

  @override
  bool operator ==(Object other) =>
      other is GroupMediaBatchForwardCellKey &&
      other.sourceIdentity == sourceIdentity &&
      other.targetKey == targetKey;

  @override
  int get hashCode => Object.hash(sourceIdentity, targetKey);

  @override
  String toString() => 'GroupMediaBatchForwardCellKey(redacted)';
}

class GroupMediaBatchForwardCellResult {
  const GroupMediaBatchForwardCellResult({
    required this.key,
    required this.target,
    required this.status,
  });

  final GroupMediaBatchForwardCellKey key;
  final ShareTargetSelection target;
  final GroupMediaBatchForwardCellStatus status;

  @override
  String toString() => 'GroupMediaBatchForwardCellResult(status: $status)';
}

class GroupMediaBatchForwardMatrix {
  GroupMediaBatchForwardMatrix({
    required Iterable<GroupMediaBatchForwardCellResult> cells,
  }) : cells = List.unmodifiable(cells) {
    final unique = <GroupMediaBatchForwardCellKey>{};
    for (final cell in this.cells) {
      if (cell.key.targetKey != cell.target.key || !unique.add(cell.key)) {
        throw ArgumentError('matrix cells must have unique coherent keys');
      }
    }
  }

  final List<GroupMediaBatchForwardCellResult> cells;

  int get sentCount => cells
      .where((cell) => cell.status == GroupMediaBatchForwardCellStatus.sent)
      .length;

  int get queuedCount => cells
      .where((cell) => cell.status == GroupMediaBatchForwardCellStatus.queued)
      .length;

  int get failedCount => cells
      .where((cell) => cell.status == GroupMediaBatchForwardCellStatus.failed)
      .length;

  Set<GroupMediaBatchForwardCellKey> get failedKeys => Set.unmodifiable(
    cells
        .where((cell) => cell.status == GroupMediaBatchForwardCellStatus.failed)
        .map((cell) => cell.key),
  );

  Set<GroupSharedMediaIdentity> get fullySettledSourceIdentities =>
      Set.unmodifiable(
        _sourceSettlement.entries
            .where((entry) => !entry.value)
            .map((entry) => entry.key),
      );

  Set<GroupSharedMediaIdentity> get failedSourceIdentities => Set.unmodifiable(
    _sourceSettlement.entries
        .where((entry) => entry.value)
        .map((entry) => entry.key),
  );

  Map<GroupSharedMediaIdentity, bool> get _sourceSettlement {
    final settlement = <GroupSharedMediaIdentity, bool>{};
    for (final cell in cells) {
      settlement.putIfAbsent(cell.key.sourceIdentity, () => false);
      if (cell.status == GroupMediaBatchForwardCellStatus.failed) {
        settlement[cell.key.sourceIdentity] = true;
      }
    }
    return settlement;
  }

  @override
  String toString() =>
      'GroupMediaBatchForwardMatrix(cellCount: ${cells.length}, '
      'sentCount: $sentCount, queuedCount: $queuedCount, '
      'failedCount: $failedCount)';
}

class GroupMediaBatchForwardAttemptResult {
  const GroupMediaBatchForwardAttemptResult.success({
    required GroupMediaBatchForwardMatrix matrix,
    required this.newlyAttemptedCellCount,
  }) : _matrix = matrix,
       denial = null,
       sourceDenial = null;

  const GroupMediaBatchForwardAttemptResult.denied({
    required this.denial,
    this.sourceDenial,
    GroupMediaBatchForwardMatrix? priorMatrix,
  }) : _matrix = priorMatrix,
       newlyAttemptedCellCount = 0;

  final GroupMediaBatchForwardMatrix? _matrix;
  final GroupMediaBatchForwardAttemptDenial? denial;
  final GroupMediaBatchForwardDenial? sourceDenial;
  final int newlyAttemptedCellCount;

  GroupMediaBatchForwardMatrix? get matrix => _matrix;
  bool get isDenied => denial != null;
}

class GroupMediaBatchForwardProgress {
  const GroupMediaBatchForwardProgress({
    required this.completedCellCount,
    required this.totalCellCount,
    required this.sourceOrdinal,
    required this.sourceCount,
    required this.phase,
  });

  final int completedCellCount;
  final int totalCellCount;
  final int sourceOrdinal;
  final int sourceCount;
  final GroupMediaBatchForwardProgressPhase phase;
}

class GroupMediaBatchForwardCompletion {
  GroupMediaBatchForwardCompletion.fromMatrix(
    GroupMediaBatchForwardMatrix matrix,
  ) : fullySettledSourceIdentities = Set.unmodifiable(
        matrix.fullySettledSourceIdentities,
      ),
      failedSourceIdentities = Set.unmodifiable(matrix.failedSourceIdentities);

  final Set<GroupSharedMediaIdentity> fullySettledSourceIdentities;
  final Set<GroupSharedMediaIdentity> failedSourceIdentities;
}

class GroupMediaBatchForwardLibraryLaunchResult {
  const GroupMediaBatchForwardLibraryLaunchResult.cancelled()
    : status = GroupMediaBatchForwardLibraryLaunchStatus.cancelled,
      denial = null,
      completion = null;

  const GroupMediaBatchForwardLibraryLaunchResult.denied(this.denial)
    : status = GroupMediaBatchForwardLibraryLaunchStatus.denied,
      completion = null;

  const GroupMediaBatchForwardLibraryLaunchResult.completed(
    GroupMediaBatchForwardCompletion value,
  ) : status = GroupMediaBatchForwardLibraryLaunchStatus.completed,
      denial = null,
      completion = value;

  final GroupMediaBatchForwardLibraryLaunchStatus status;
  final GroupMediaBatchForwardDenial? denial;
  final GroupMediaBatchForwardCompletion? completion;
}

typedef GroupMediaBatchForwardLibraryLaunch =
    Future<GroupMediaBatchForwardLibraryLaunchResult> Function(
      List<GroupSharedMediaIdentity> sourceIdentities,
    );
typedef GroupMediaBatchForwardProgressCallback =
    void Function(GroupMediaBatchForwardProgress progress);
typedef GroupMediaBatchForwardSourceRevalidator =
    Future<GroupMediaBatchForwardBuildResult> Function(
      GroupMediaBatchForwardDraft draft,
    );
typedef GroupMediaBatchForwardSingleDelivery =
    Future<ShareBatchDeliveryResult> Function({
      required GroupMediaForwardRequest request,
      String? caption,
      required List<ShareTargetSelection> targets,
    });

/// Source-major composition over the accepted one-source Plan-236/240
/// delivery boundary. Sent/queued cells are immutable; an in-route retry
/// revalidates all failed sources first and invokes only failed cells.
class GroupMediaBatchForwardDeliveryCoordinator {
  GroupMediaBatchForwardDeliveryCoordinator({
    required GroupMediaBatchForwardSourceRevalidator revalidateForDispatch,
    required GroupMediaBatchForwardSingleDelivery deliverSingle,
  }) : _revalidateForDispatch = revalidateForDispatch,
       _deliverSingle = deliverSingle;

  final GroupMediaBatchForwardSourceRevalidator _revalidateForDispatch;
  final GroupMediaBatchForwardSingleDelivery _deliverSingle;

  Future<GroupMediaBatchForwardAttemptResult> deliverInitial({
    required GroupMediaBatchForwardDraft draft,
    required List<ShareTargetSelection> targets,
    GroupMediaBatchForwardProgressCallback? onProgress,
  }) async {
    if (!_validDraft(draft) || !_validTargets(targets)) {
      return const GroupMediaBatchForwardAttemptResult.denied(
        denial: GroupMediaBatchForwardAttemptDenial.invalidRequest,
      );
    }
    final revalidation = await _revalidate(draft);
    final canonical = revalidation.draft;
    if (canonical == null) {
      return GroupMediaBatchForwardAttemptResult.denied(
        denial: GroupMediaBatchForwardAttemptDenial.sourceUnavailable,
        sourceDenial: revalidation.denial,
      );
    }

    final pending = <GroupSharedMediaIdentity, List<ShareTargetSelection>>{
      for (final item in canonical.items)
        item.identity: List.unmodifiable(targets),
    };
    final cells = await _deliverPendingCells(
      draft: canonical,
      pendingTargetsBySource: pending,
      totalCellCount: canonical.items.length * targets.length,
      onProgress: onProgress,
    );
    final matrix = GroupMediaBatchForwardMatrix(cells: cells);
    return GroupMediaBatchForwardAttemptResult.success(
      matrix: matrix,
      newlyAttemptedCellCount: cells.length,
    );
  }

  Future<GroupMediaBatchForwardAttemptResult> retryFailed({
    required GroupMediaBatchForwardDraft draft,
    required GroupMediaBatchForwardMatrix priorMatrix,
    GroupMediaBatchForwardProgressCallback? onProgress,
  }) async {
    final failedCells = priorMatrix.cells
        .where((cell) => cell.status == GroupMediaBatchForwardCellStatus.failed)
        .toList(growable: false);
    if (failedCells.isEmpty) {
      return GroupMediaBatchForwardAttemptResult.success(
        matrix: priorMatrix,
        newlyAttemptedCellCount: 0,
      );
    }
    if (!_validDraft(draft) || !_matrixBelongsToDraft(priorMatrix, draft)) {
      return GroupMediaBatchForwardAttemptResult.denied(
        denial: GroupMediaBatchForwardAttemptDenial.invalidRequest,
        priorMatrix: priorMatrix,
      );
    }

    final failedSources = failedCells
        .map((cell) => cell.key.sourceIdentity)
        .toSet();
    final subset = GroupMediaBatchForwardDraft(
      sourceGroupId: draft.sourceGroupId,
      sourceKind: draft.sourceKind,
      items: [
        for (final item in draft.items)
          if (failedSources.contains(item.identity)) item,
      ],
    );
    if (subset.items.length != failedSources.length) {
      return GroupMediaBatchForwardAttemptResult.denied(
        denial: GroupMediaBatchForwardAttemptDenial.invalidRequest,
        priorMatrix: priorMatrix,
      );
    }
    final revalidation = await _revalidate(subset, minimumItems: 1);
    final canonical = revalidation.draft;
    if (canonical == null) {
      return GroupMediaBatchForwardAttemptResult.denied(
        denial: GroupMediaBatchForwardAttemptDenial.sourceUnavailable,
        sourceDenial: revalidation.denial,
        priorMatrix: priorMatrix,
      );
    }

    final pending = <GroupSharedMediaIdentity, List<ShareTargetSelection>>{};
    for (final item in canonical.items) {
      pending[item.identity] = [
        for (final cell in failedCells)
          if (cell.key.sourceIdentity == item.identity) cell.target,
      ];
    }
    final attempted = await _deliverPendingCells(
      draft: canonical,
      pendingTargetsBySource: pending,
      totalCellCount: failedCells.length,
      onProgress: onProgress,
    );
    final updates = {for (final cell in attempted) cell.key: cell};
    if (updates.length != failedCells.length) {
      return GroupMediaBatchForwardAttemptResult.denied(
        denial: GroupMediaBatchForwardAttemptDenial.invalidRequest,
        priorMatrix: priorMatrix,
      );
    }

    final merged = GroupMediaBatchForwardMatrix(
      cells: [
        for (final cell in priorMatrix.cells)
          if (cell.status == GroupMediaBatchForwardCellStatus.failed)
            updates[cell.key] ?? cell
          else
            cell,
      ],
    );
    return GroupMediaBatchForwardAttemptResult.success(
      matrix: merged,
      newlyAttemptedCellCount: attempted.length,
    );
  }

  Future<_GroupMediaBatchForwardRevalidation> _revalidate(
    GroupMediaBatchForwardDraft draft, {
    int minimumItems = kGroupMediaBatchForwardMinItems,
  }) async {
    final GroupMediaBatchForwardBuildResult result;
    try {
      result = await _revalidateForDispatch(draft);
    } catch (_) {
      return const _GroupMediaBatchForwardRevalidation.denied(
        GroupMediaBatchForwardDenial.sourceUnavailable,
      );
    }
    final canonical = result.draft;
    if (!result.isReady || canonical == null) {
      return _GroupMediaBatchForwardRevalidation.denied(
        result.denial ?? GroupMediaBatchForwardDenial.sourceUnavailable,
      );
    }
    if (!_validDraft(canonical, minimumItems: minimumItems)) {
      return const _GroupMediaBatchForwardRevalidation.denied(
        GroupMediaBatchForwardDenial.invalidSelection,
      );
    }
    if (canonical.sourceGroupId != draft.sourceGroupId ||
        canonical.sourceKind != draft.sourceKind ||
        canonical.items.length != draft.items.length) {
      return const _GroupMediaBatchForwardRevalidation.denied(
        GroupMediaBatchForwardDenial.sourceScopeChanged,
      );
    }
    for (var index = 0; index < canonical.items.length; index++) {
      final current = canonical.items[index];
      final original = draft.items[index];
      if (current.identity != original.identity ||
          current.caption != original.caption ||
          current.request.provenance.operationDedupKey !=
              original.request.provenance.operationDedupKey) {
        return const _GroupMediaBatchForwardRevalidation.denied(
          GroupMediaBatchForwardDenial.sourceScopeChanged,
        );
      }
    }
    return _GroupMediaBatchForwardRevalidation.ready(canonical);
  }

  Future<List<GroupMediaBatchForwardCellResult>> _deliverPendingCells({
    required GroupMediaBatchForwardDraft draft,
    required Map<GroupSharedMediaIdentity, List<ShareTargetSelection>>
    pendingTargetsBySource,
    required int totalCellCount,
    GroupMediaBatchForwardProgressCallback? onProgress,
  }) async {
    final cells = <GroupMediaBatchForwardCellResult>[];
    var completedCellCount = 0;
    for (var sourceIndex = 0; sourceIndex < draft.items.length; sourceIndex++) {
      final item = draft.items[sourceIndex];
      final targets = pendingTargetsBySource[item.identity] ?? const [];
      if (targets.isEmpty) continue;

      _emitProgress(
        onProgress,
        completedCellCount: completedCellCount,
        totalCellCount: totalCellCount,
        sourceOrdinal: sourceIndex + 1,
        sourceCount: draft.items.length,
        phase: GroupMediaBatchForwardProgressPhase.uploading,
      );
      ShareBatchDeliveryResult? delivery;
      try {
        delivery = await _deliverSingle(
          request: item.request,
          caption: item.caption,
          targets: List.unmodifiable(targets),
        );
      } catch (_) {
        delivery = null;
      }

      _emitProgress(
        onProgress,
        completedCellCount: completedCellCount,
        totalCellCount: totalCellCount,
        sourceOrdinal: sourceIndex + 1,
        sourceCount: draft.items.length,
        phase: GroupMediaBatchForwardProgressPhase.sending,
      );
      final byTarget = <String, List<ShareBatchTargetResult>>{};
      if (delivery != null && !delivery.hasSkippedOversizedGifs) {
        final requestedKeys = targets.map((target) => target.key).toSet();
        for (final result in delivery.results) {
          if (!requestedKeys.contains(result.target.key)) continue;
          byTarget.putIfAbsent(result.target.key, () => []).add(result);
        }
      }
      for (final target in targets) {
        final ordinaryResults = byTarget[target.key];
        final ordinary = ordinaryResults?.length == 1
            ? ordinaryResults!.single
            : null;
        cells.add(
          GroupMediaBatchForwardCellResult(
            key: GroupMediaBatchForwardCellKey(
              sourceIdentity: item.identity,
              targetKey: target.key,
            ),
            target: target,
            status: _cellStatus(ordinary?.status),
          ),
        );
        completedCellCount++;
      }
    }
    return cells;
  }

  GroupMediaBatchForwardCellStatus _cellStatus(
    ShareBatchTargetStatus? status,
  ) => switch (status) {
    ShareBatchTargetStatus.sent => GroupMediaBatchForwardCellStatus.sent,
    ShareBatchTargetStatus.queued => GroupMediaBatchForwardCellStatus.queued,
    ShareBatchTargetStatus.failed ||
    null => GroupMediaBatchForwardCellStatus.failed,
  };

  bool _validDraft(
    GroupMediaBatchForwardDraft draft, {
    int minimumItems = kGroupMediaBatchForwardMinItems,
  }) {
    if (draft.sourceGroupId.trim().isEmpty ||
        draft.items.length < minimumItems ||
        draft.items.length > kGroupMediaBatchForwardMaxItems) {
      return false;
    }
    final identities = <GroupSharedMediaIdentity>{};
    final tokens = <String>{};
    for (final item in draft.items) {
      final request = item.request;
      final token = request.provenance.operationDedupKey.trim();
      if (item.identity.groupId != draft.sourceGroupId ||
          item.identity.messageId.trim().isEmpty ||
          item.identity.attachmentId.trim().isEmpty ||
          !identities.add(item.identity) ||
          request.groupId != item.identity.groupId ||
          request.messageId != item.identity.messageId ||
          request.attachmentId != item.identity.attachmentId ||
          (draft.sourceKind == GroupMediaBatchForwardSourceKind.announcement) !=
              (request is AnnouncementMediaForwardRequest) ||
          item.resolvedPath.trim().isEmpty ||
          item.sizeBytes <= 0 ||
          token.isEmpty ||
          !tokens.add(token)) {
        return false;
      }
    }
    return true;
  }

  bool _validTargets(List<ShareTargetSelection> targets) {
    if (targets.isEmpty) return false;
    final keys = <String>{};
    for (final target in targets) {
      if (target.key.trim().isEmpty || !keys.add(target.key)) return false;
    }
    return true;
  }

  bool _matrixBelongsToDraft(
    GroupMediaBatchForwardMatrix matrix,
    GroupMediaBatchForwardDraft draft,
  ) {
    final sourceIdentities = draft.items.map((item) => item.identity).toSet();
    final keys = <GroupMediaBatchForwardCellKey>{};
    for (final cell in matrix.cells) {
      if (!sourceIdentities.contains(cell.key.sourceIdentity) ||
          cell.key.targetKey != cell.target.key ||
          !keys.add(cell.key)) {
        return false;
      }
    }
    return true;
  }

  void _emitProgress(
    GroupMediaBatchForwardProgressCallback? callback, {
    required int completedCellCount,
    required int totalCellCount,
    required int sourceOrdinal,
    required int sourceCount,
    required GroupMediaBatchForwardProgressPhase phase,
  }) {
    callback?.call(
      GroupMediaBatchForwardProgress(
        completedCellCount: completedCellCount,
        totalCellCount: totalCellCount,
        sourceOrdinal: sourceOrdinal,
        sourceCount: sourceCount,
        phase: phase,
      ),
    );
  }
}

class _GroupMediaBatchForwardRevalidation {
  const _GroupMediaBatchForwardRevalidation.ready(this.draft) : denial = null;

  const _GroupMediaBatchForwardRevalidation.denied(this.denial) : draft = null;

  final GroupMediaBatchForwardDraft? draft;
  final GroupMediaBatchForwardDenial? denial;
}
