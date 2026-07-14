import 'package:flutter_app/core/services/share_intent_model.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/build_direct_media_library_batch_forward.dart';
import 'package:flutter_app/features/conversation/application/received_media_action_controller.dart';

import 'share_batch_delivery_coordinator.dart';
import 'share_target_selection.dart';

enum DirectMediaBatchForwardCellStatus { sent, queued, failed }

enum DirectMediaBatchForwardAttemptDenial { invalidRequest, sourceUnavailable }

enum DirectMediaBatchForwardProgressPhase { uploading, sending }

enum DirectMediaBatchForwardLibraryLaunchStatus {
  cancelled,
  sourceUnavailable,
  completed,
}

class DirectMediaBatchForwardCellKey {
  DirectMediaBatchForwardCellKey({
    required this.sourceIdentity,
    required this.contactPeerId,
  }) {
    if (sourceIdentity.messageId.trim().isEmpty ||
        sourceIdentity.attachmentId.trim().isEmpty) {
      throw ArgumentError('sourceIdentity must be complete');
    }
    if (contactPeerId.trim().isEmpty) {
      throw ArgumentError('contactPeerId must be nonblank');
    }
  }

  final DirectReceivedMediaActionIdentity sourceIdentity;
  final String contactPeerId;

  @override
  bool operator ==(Object other) =>
      other is DirectMediaBatchForwardCellKey &&
      other.sourceIdentity == sourceIdentity &&
      other.contactPeerId == contactPeerId;

  @override
  int get hashCode => Object.hash(sourceIdentity, contactPeerId);

  @override
  String toString() => 'DirectMediaBatchForwardCellKey(redacted)';
}

class DirectMediaBatchForwardCellResult {
  const DirectMediaBatchForwardCellResult({
    required this.key,
    required this.status,
  });

  final DirectMediaBatchForwardCellKey key;
  final DirectMediaBatchForwardCellStatus status;

  @override
  String toString() => 'DirectMediaBatchForwardCellResult(status: $status)';
}

class DirectMediaBatchForwardMatrix {
  DirectMediaBatchForwardMatrix({
    required Iterable<DirectMediaBatchForwardCellResult> cells,
  }) : cells = List.unmodifiable(cells) {
    final unique = <DirectMediaBatchForwardCellKey>{};
    for (final cell in this.cells) {
      if (!unique.add(cell.key)) {
        throw ArgumentError('matrix cell keys must be unique');
      }
    }
  }

  final List<DirectMediaBatchForwardCellResult> cells;

  int get sentCount => cells
      .where((cell) => cell.status == DirectMediaBatchForwardCellStatus.sent)
      .length;

  int get queuedCount => cells
      .where((cell) => cell.status == DirectMediaBatchForwardCellStatus.queued)
      .length;

  int get failedCount => cells
      .where((cell) => cell.status == DirectMediaBatchForwardCellStatus.failed)
      .length;

  Set<DirectMediaBatchForwardCellKey> get failedKeys => Set.unmodifiable(
    cells
        .where(
          (cell) => cell.status == DirectMediaBatchForwardCellStatus.failed,
        )
        .map((cell) => cell.key),
  );

  Set<DirectReceivedMediaActionIdentity> get fullySettledSourceIdentities =>
      Set.unmodifiable(
        _sourceSettlement.entries
            .where((entry) => !entry.value)
            .map((entry) => entry.key),
      );

  Set<DirectReceivedMediaActionIdentity> get failedSourceIdentities =>
      Set.unmodifiable(
        _sourceSettlement.entries
            .where((entry) => entry.value)
            .map((entry) => entry.key),
      );

  Map<DirectReceivedMediaActionIdentity, bool> get _sourceSettlement {
    final settlement = <DirectReceivedMediaActionIdentity, bool>{};
    for (final cell in cells) {
      settlement.putIfAbsent(cell.key.sourceIdentity, () => false);
      if (cell.status == DirectMediaBatchForwardCellStatus.failed) {
        settlement[cell.key.sourceIdentity] = true;
      }
    }
    return settlement;
  }

  @override
  String toString() =>
      'DirectMediaBatchForwardMatrix(cellCount: ${cells.length}, '
      'sentCount: $sentCount, queuedCount: $queuedCount, '
      'failedCount: $failedCount)';
}

class DirectMediaBatchForwardAttemptResult {
  const DirectMediaBatchForwardAttemptResult.success({
    required DirectMediaBatchForwardMatrix matrix,
    required this.newlyAttemptedCellCount,
  }) : _matrix = matrix,
       _denial = null;

  const DirectMediaBatchForwardAttemptResult.denied({
    required DirectMediaBatchForwardAttemptDenial denial,
    DirectMediaBatchForwardMatrix? priorMatrix,
  }) : _matrix = priorMatrix,
       _denial = denial,
       newlyAttemptedCellCount = 0;

  final DirectMediaBatchForwardMatrix? _matrix;
  final DirectMediaBatchForwardAttemptDenial? _denial;
  final int newlyAttemptedCellCount;

  DirectMediaBatchForwardMatrix? get matrix => _matrix;
  DirectMediaBatchForwardAttemptDenial? get denial => _denial;
  bool get isDenied => denial != null;

  @override
  String toString() => isDenied
      ? 'DirectMediaBatchForwardAttemptResult(denied: $denial, '
            'retainedCellCount: ${matrix?.cells.length ?? 0})'
      : 'DirectMediaBatchForwardAttemptResult(success, '
            'cellCount: ${matrix?.cells.length ?? 0}, '
            'newlyAttemptedCellCount: $newlyAttemptedCellCount)';
}

class DirectMediaBatchForwardProgress {
  const DirectMediaBatchForwardProgress({
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
  final DirectMediaBatchForwardProgressPhase phase;

  @override
  String toString() =>
      'DirectMediaBatchForwardProgress(completedCellCount: '
      '$completedCellCount, totalCellCount: $totalCellCount, '
      'sourceOrdinal: $sourceOrdinal, sourceCount: $sourceCount, '
      'phase: $phase)';
}

class DirectMediaBatchForwardCompletion {
  DirectMediaBatchForwardCompletion.fromMatrix(
    DirectMediaBatchForwardMatrix matrix,
  ) : fullySettledSourceIdentities = Set.unmodifiable(
        matrix.fullySettledSourceIdentities,
      ),
      failedSourceIdentities = Set.unmodifiable(matrix.failedSourceIdentities);

  final Set<DirectReceivedMediaActionIdentity> fullySettledSourceIdentities;
  final Set<DirectReceivedMediaActionIdentity> failedSourceIdentities;

  @override
  String toString() =>
      'DirectMediaBatchForwardCompletion(fullySettledSourceCount: '
      '${fullySettledSourceIdentities.length}, failedSourceCount: '
      '${failedSourceIdentities.length})';
}

class DirectMediaBatchForwardLibraryLaunchResult {
  const DirectMediaBatchForwardLibraryLaunchResult.cancelled()
    : status = DirectMediaBatchForwardLibraryLaunchStatus.cancelled,
      _completion = null;

  const DirectMediaBatchForwardLibraryLaunchResult.sourceUnavailable()
    : status = DirectMediaBatchForwardLibraryLaunchStatus.sourceUnavailable,
      _completion = null;

  const DirectMediaBatchForwardLibraryLaunchResult.completed(
    DirectMediaBatchForwardCompletion completion,
  ) : status = DirectMediaBatchForwardLibraryLaunchStatus.completed,
      _completion = completion;

  final DirectMediaBatchForwardLibraryLaunchStatus status;
  final DirectMediaBatchForwardCompletion? _completion;

  DirectMediaBatchForwardCompletion? get completion => _completion;
  bool get isCancelled =>
      status == DirectMediaBatchForwardLibraryLaunchStatus.cancelled;
  bool get isSourceUnavailable =>
      status == DirectMediaBatchForwardLibraryLaunchStatus.sourceUnavailable;
  bool get isCompleted =>
      status == DirectMediaBatchForwardLibraryLaunchStatus.completed;

  @override
  String toString() =>
      'DirectMediaBatchForwardLibraryLaunchResult(status: $status, '
      'hasCompletion: ${completion != null})';
}

typedef DirectMediaBatchForwardLibraryLaunch =
    Future<DirectMediaBatchForwardLibraryLaunchResult> Function(
      List<DirectReceivedMediaActionIdentity> sourceIdentities,
    );

typedef DirectMediaBatchForwardProgressCallback =
    void Function(DirectMediaBatchForwardProgress progress);

typedef DirectMediaBatchForwardSourceRevalidator =
    Future<DirectMediaLibraryBatchForwardResult> Function({
      required String contactPeerId,
      required DirectMediaLibraryBatchForwardDraft draft,
    });

typedef DirectMediaBatchForwardStrictDelivery =
    Future<ShareBatchDeliveryResult> Function({
      required ShareIntent shareIntent,
      required List<ContactModel> contacts,
      ShareBatchDeliveryProgressCallback? onProgress,
    });

class DirectMediaBatchForwardDeliveryCoordinator {
  DirectMediaBatchForwardDeliveryCoordinator({
    required DirectMediaBatchForwardSourceRevalidator revalidateForDispatch,
    required ContactRepository contactRepository,
    required DirectMediaBatchForwardStrictDelivery deliverStrict,
  }) : _revalidateForDispatch = revalidateForDispatch,
       _contactRepository = contactRepository,
       _deliverStrict = deliverStrict;

  final DirectMediaBatchForwardSourceRevalidator _revalidateForDispatch;
  final ContactRepository _contactRepository;
  final DirectMediaBatchForwardStrictDelivery _deliverStrict;

  Future<DirectMediaBatchForwardAttemptResult> deliverInitial({
    required String sourceContactPeerId,
    required DirectMediaLibraryBatchForwardDraft draft,
    required List<String> contactPeerIds,
    DirectMediaBatchForwardProgressCallback? onProgress,
  }) async {
    if (!_validSourceContact(sourceContactPeerId) ||
        !_validDraft(draft) ||
        !_validContactPeerIds(contactPeerIds)) {
      return const DirectMediaBatchForwardAttemptResult.denied(
        denial: DirectMediaBatchForwardAttemptDenial.invalidRequest,
      );
    }

    final canonical = await _revalidate(
      sourceContactPeerId: sourceContactPeerId,
      draft: draft,
    );
    if (canonical == null) {
      return const DirectMediaBatchForwardAttemptResult.denied(
        denial: DirectMediaBatchForwardAttemptDenial.sourceUnavailable,
      );
    }

    final contacts = await _loadCurrentContacts(contactPeerIds);
    final pendingBySource = <DirectReceivedMediaActionIdentity, List<String>>{
      for (final item in canonical.items)
        item.identity: List.unmodifiable(contactPeerIds),
    };
    final attempt = await _deliverPendingCells(
      draft: canonical,
      pendingContactPeerIdsBySource: pendingBySource,
      currentContacts: contacts,
      totalCellCount: canonical.items.length * contactPeerIds.length,
      onProgress: onProgress,
    );
    final matrix = DirectMediaBatchForwardMatrix(cells: attempt.cells);
    return DirectMediaBatchForwardAttemptResult.success(
      matrix: matrix,
      newlyAttemptedCellCount: attempt.cells.length,
    );
  }

  Future<DirectMediaBatchForwardAttemptResult> retryFailed({
    required String sourceContactPeerId,
    required DirectMediaLibraryBatchForwardDraft draft,
    required DirectMediaBatchForwardMatrix priorMatrix,
    DirectMediaBatchForwardProgressCallback? onProgress,
  }) async {
    final failedCells = priorMatrix.cells
        .where(
          (cell) => cell.status == DirectMediaBatchForwardCellStatus.failed,
        )
        .toList(growable: false);
    if (failedCells.isEmpty) {
      return DirectMediaBatchForwardAttemptResult.success(
        matrix: priorMatrix,
        newlyAttemptedCellCount: 0,
      );
    }

    if (!_validSourceContact(sourceContactPeerId) || !_validDraft(draft)) {
      return DirectMediaBatchForwardAttemptResult.denied(
        denial: DirectMediaBatchForwardAttemptDenial.invalidRequest,
        priorMatrix: priorMatrix,
      );
    }

    final failedSourceIdentities = <DirectReceivedMediaActionIdentity>{};
    final failedContactPeerIds = <String>[];
    final seenContacts = <String>{};
    final failedKeys = <DirectMediaBatchForwardCellKey>{};
    for (final cell in failedCells) {
      if (!_validIdentity(cell.key.sourceIdentity) ||
          !_validContactPeerId(cell.key.contactPeerId) ||
          !failedKeys.add(cell.key)) {
        return DirectMediaBatchForwardAttemptResult.denied(
          denial: DirectMediaBatchForwardAttemptDenial.invalidRequest,
          priorMatrix: priorMatrix,
        );
      }
      failedSourceIdentities.add(cell.key.sourceIdentity);
      if (seenContacts.add(cell.key.contactPeerId)) {
        failedContactPeerIds.add(cell.key.contactPeerId);
      }
    }

    final subsetItems = draft.items
        .where((item) => failedSourceIdentities.contains(item.identity))
        .toList(growable: false);
    if (subsetItems.length != failedSourceIdentities.length) {
      return DirectMediaBatchForwardAttemptResult.denied(
        denial: DirectMediaBatchForwardAttemptDenial.invalidRequest,
        priorMatrix: priorMatrix,
      );
    }
    final subset = DirectMediaLibraryBatchForwardDraft(items: subsetItems);
    final canonical = await _revalidate(
      sourceContactPeerId: sourceContactPeerId,
      draft: subset,
    );
    if (canonical == null) {
      return DirectMediaBatchForwardAttemptResult.denied(
        denial: DirectMediaBatchForwardAttemptDenial.sourceUnavailable,
        priorMatrix: priorMatrix,
      );
    }

    final contacts = await _loadCurrentContacts(failedContactPeerIds);
    final pendingBySource = <DirectReceivedMediaActionIdentity, List<String>>{};
    for (final item in canonical.items) {
      pendingBySource[item.identity] = [
        for (final cell in failedCells)
          if (cell.key.sourceIdentity == item.identity) cell.key.contactPeerId,
      ];
    }
    final attempt = await _deliverPendingCells(
      draft: canonical,
      pendingContactPeerIdsBySource: pendingBySource,
      currentContacts: contacts,
      totalCellCount: failedCells.length,
      onProgress: onProgress,
    );
    final updates =
        <DirectMediaBatchForwardCellKey, DirectMediaBatchForwardCellResult>{
          for (final cell in attempt.cells) cell.key: cell,
        };
    if (updates.length != failedCells.length) {
      return DirectMediaBatchForwardAttemptResult.denied(
        denial: DirectMediaBatchForwardAttemptDenial.invalidRequest,
        priorMatrix: priorMatrix,
      );
    }

    final merged = DirectMediaBatchForwardMatrix(
      cells: [
        for (final cell in priorMatrix.cells)
          if (cell.status == DirectMediaBatchForwardCellStatus.failed)
            updates[cell.key] ?? cell
          else
            cell,
      ],
    );
    return DirectMediaBatchForwardAttemptResult.success(
      matrix: merged,
      newlyAttemptedCellCount: failedCells.length,
    );
  }

  Future<DirectMediaLibraryBatchForwardDraft?> _revalidate({
    required String sourceContactPeerId,
    required DirectMediaLibraryBatchForwardDraft draft,
  }) async {
    final DirectMediaLibraryBatchForwardResult result;
    try {
      result = await _revalidateForDispatch(
        contactPeerId: sourceContactPeerId,
        draft: draft,
      );
    } catch (_) {
      return null;
    }
    final canonical = result.draft;
    if (!result.isReady || canonical == null || !_validDraft(canonical)) {
      return null;
    }

    final originals = {for (final item in draft.items) item.identity: item};
    if (canonical.items.length != originals.length) return null;
    for (final item in canonical.items) {
      final original = originals[item.identity];
      if (original == null ||
          item.caption != original.caption ||
          item.forwardProvenance.operationDedupKey !=
              original.forwardProvenance.operationDedupKey ||
          item.resolvedPath.trim().isEmpty) {
        return null;
      }
    }
    return canonical;
  }

  Future<Map<String, ContactModel?>> _loadCurrentContacts(
    List<String> contactPeerIds,
  ) async {
    final contacts = <String, ContactModel?>{};
    for (final peerId in contactPeerIds) {
      try {
        final current = await _contactRepository.getContact(peerId);
        contacts[peerId] =
            current != null &&
                current.peerId == peerId &&
                !current.isArchived &&
                !current.isBlocked
            ? current
            : null;
      } catch (_) {
        contacts[peerId] = null;
      }
    }
    return contacts;
  }

  Future<_DirectMediaBatchForwardAttemptCells> _deliverPendingCells({
    required DirectMediaLibraryBatchForwardDraft draft,
    required Map<DirectReceivedMediaActionIdentity, List<String>>
    pendingContactPeerIdsBySource,
    required Map<String, ContactModel?> currentContacts,
    required int totalCellCount,
    DirectMediaBatchForwardProgressCallback? onProgress,
  }) async {
    final cells = <DirectMediaBatchForwardCellResult>[];
    var completedCellCount = 0;

    for (var sourceIndex = 0; sourceIndex < draft.items.length; sourceIndex++) {
      final item = draft.items[sourceIndex];
      final pendingPeerIds =
          pendingContactPeerIdsBySource[item.identity] ?? const <String>[];
      final eligibleContacts = <ContactModel>[];
      for (final peerId in pendingPeerIds) {
        final current = currentContacts[peerId];
        if (current != null) eligibleContacts.add(current);
      }

      Map<String, DirectMediaBatchForwardCellStatus> ordinaryStatuses = {};
      if (eligibleContacts.isNotEmpty) {
        _emitProgress(
          onProgress,
          completedCellCount: completedCellCount,
          totalCellCount: totalCellCount,
          sourceOrdinal: sourceIndex + 1,
          sourceCount: draft.items.length,
          phase: DirectMediaBatchForwardProgressPhase.uploading,
        );
        final intent = ShareIntent(
          type: item.caption.isEmpty
              ? ShareIntentType.files
              : ShareIntentType.mixed,
          text: item.caption.isEmpty ? null : item.caption,
          filePaths: [item.resolvedPath],
          forwardProvenance: item.forwardProvenance,
        );
        try {
          final ordinary = await _deliverStrict(
            shareIntent: intent,
            contacts: List.unmodifiable(eligibleContacts),
            onProgress: onProgress == null
                ? null
                : (progress) {
                    _emitProgress(
                      onProgress,
                      completedCellCount: completedCellCount,
                      totalCellCount: totalCellCount,
                      sourceOrdinal: sourceIndex + 1,
                      sourceCount: draft.items.length,
                      phase: progress.phase == ShareBatchDeliveryPhase.uploading
                          ? DirectMediaBatchForwardProgressPhase.uploading
                          : DirectMediaBatchForwardProgressPhase.sending,
                    );
                  },
          );
          ordinaryStatuses = _mapOrdinaryStatuses(ordinary, eligibleContacts);
        } catch (_) {
          ordinaryStatuses = {};
        }
      }

      for (final peerId in pendingPeerIds) {
        cells.add(
          DirectMediaBatchForwardCellResult(
            key: DirectMediaBatchForwardCellKey(
              sourceIdentity: item.identity,
              contactPeerId: peerId,
            ),
            status: currentContacts[peerId] == null
                ? DirectMediaBatchForwardCellStatus.failed
                : ordinaryStatuses[peerId] ??
                      DirectMediaBatchForwardCellStatus.failed,
          ),
        );
      }
      completedCellCount += pendingPeerIds.length;
      _emitProgress(
        onProgress,
        completedCellCount: completedCellCount,
        totalCellCount: totalCellCount,
        sourceOrdinal: sourceIndex + 1,
        sourceCount: draft.items.length,
        phase: DirectMediaBatchForwardProgressPhase.sending,
      );
    }

    return _DirectMediaBatchForwardAttemptCells(cells);
  }

  Map<String, DirectMediaBatchForwardCellStatus> _mapOrdinaryStatuses(
    ShareBatchDeliveryResult ordinary,
    List<ContactModel> eligibleContacts,
  ) {
    final eligiblePeerIds = {
      for (final contact in eligibleContacts) contact.peerId,
    };
    final candidates = <String, List<DirectMediaBatchForwardCellStatus>>{};
    for (final result in ordinary.results) {
      if (result.target.kind != ShareTargetSelectionKind.contact) continue;
      final peerId = result.target.requireContact.peerId;
      if (!eligiblePeerIds.contains(peerId)) continue;
      candidates.putIfAbsent(peerId, () => []).add(switch (result.status) {
        ShareBatchTargetStatus.sent => DirectMediaBatchForwardCellStatus.sent,
        ShareBatchTargetStatus.queued =>
          DirectMediaBatchForwardCellStatus.queued,
        ShareBatchTargetStatus.failed =>
          DirectMediaBatchForwardCellStatus.failed,
      });
    }

    return {
      for (final peerId in eligiblePeerIds)
        peerId: candidates[peerId]?.length == 1
            ? candidates[peerId]!.single
            : DirectMediaBatchForwardCellStatus.failed,
    };
  }

  void _emitProgress(
    DirectMediaBatchForwardProgressCallback? callback, {
    required int completedCellCount,
    required int totalCellCount,
    required int sourceOrdinal,
    required int sourceCount,
    required DirectMediaBatchForwardProgressPhase phase,
  }) {
    if (callback == null) return;
    try {
      callback(
        DirectMediaBatchForwardProgress(
          completedCellCount: completedCellCount,
          totalCellCount: totalCellCount,
          sourceOrdinal: sourceOrdinal,
          sourceCount: sourceCount,
          phase: phase,
        ),
      );
    } catch (_) {
      // Rendering/progress observation cannot change delivery settlement.
    }
  }

  bool _validSourceContact(String peerId) => _validContactPeerId(peerId);

  bool _validContactPeerIds(List<String> peerIds) {
    if (peerIds.isEmpty) return false;
    final unique = <String>{};
    for (final peerId in peerIds) {
      if (!_validContactPeerId(peerId) || !unique.add(peerId)) return false;
    }
    return true;
  }

  bool _validContactPeerId(String peerId) =>
      peerId.isNotEmpty && peerId == peerId.trim();

  bool _validIdentity(DirectReceivedMediaActionIdentity identity) =>
      identity.messageId.trim().isNotEmpty &&
      identity.attachmentId.trim().isNotEmpty;

  bool _validDraft(DirectMediaLibraryBatchForwardDraft draft) {
    if (draft.items.isEmpty || draft.items.length > 10) return false;
    final identities = <DirectReceivedMediaActionIdentity>{};
    final tokens = <String>{};
    for (final item in draft.items) {
      final token = item.forwardProvenance.operationDedupKey;
      if (!_validIdentity(item.identity) ||
          !identities.add(item.identity) ||
          token.trim().isEmpty ||
          !tokens.add(token)) {
        return false;
      }
    }
    return true;
  }
}

class _DirectMediaBatchForwardAttemptCells {
  const _DirectMediaBatchForwardAttemptCells(this.cells);

  final List<DirectMediaBatchForwardCellResult> cells;
}
