import 'dart:io';

import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/received_media_egress.dart';
import 'package:flutter_app/core/media/received_media_egress_service.dart';
import 'package:uuid/uuid.dart';

import '../domain/repositories/media_attachment_repository.dart';
import 'received_media_action_controller.dart';

/// 233: settled outcome for ONE attachment in a batch Save/Share dispatch.
///
/// Exactly one of [denial] (a plan-231 current-row preflight denial — this
/// item never reached the native boundary) or [itemOutcome] (the typed
/// native/structural per-item result) is set; a share presentation carries
/// neither and reports through [succeeded].
class DirectMediaLibraryBatchItemOutcome {
  const DirectMediaLibraryBatchItemOutcome({
    required this.attachmentId,
    required this.succeeded,
    this.denial,
    this.itemOutcome,
  });

  final String attachmentId;
  final bool succeeded;
  final DirectMediaEgressDenial? denial;
  final MediaEgressItemOutcome? itemOutcome;
}

/// 233: the merged result of one batch Save/Share dispatch — per-item
/// preflight denials plus the single native call's typed outcomes.
class DirectMediaLibraryBatchResult {
  const DirectMediaLibraryBatchResult({
    required this.items,
    required this.egressResult,
  });

  /// One outcome per dispatched attachment, in dispatch order.
  final List<DirectMediaLibraryBatchItemOutcome> items;

  /// The untouched result of the single egress-service call, or null when
  /// every item failed preflight and no service call was made.
  final MediaEgressResult? egressResult;

  bool get wasCancelled =>
      egressResult?.outcome == MediaEgressOutcome.cancelled;

  Set<String> get succeededIds => {
    for (final item in items)
      if (item.succeeded) item.attachmentId,
  };

  /// Items that stay selected for truthful failed-only retry.
  Set<String> get failedIds => {
    for (final item in items)
      if (!item.succeeded) item.attachmentId,
  };
}

/// Dispatch seam the library surface calls with `1..kMaxMediaEgressItems`
/// scoped-page identities. Production wires this to
/// [DirectMediaLibraryBatchActionsCoordinator.performBatchEgress]; tests
/// inject recorders.
typedef DirectMediaLibraryEgressDispatch =
    Future<DirectMediaLibraryBatchResult> Function(
      List<DirectReceivedMediaActionIdentity> identities,
      MediaEgressDestination destination,
    );

String _defaultEgressRequestId() => const Uuid().v4();

bool _defaultFileExists(String resolvedPath) => File(resolvedPath).existsSync();

/// 233: batch Save/Share over the shared plan-231 current-row qualification.
///
/// Every dispatched identity is re-qualified against its RELOADED incoming
/// parent and current [MediaAttachmentRepository] direct row — library/viewer
/// path and MIME snapshots are presentation state, never egress authority.
/// The qualified candidates go to the plan-227 service in ONE list-capable
/// call (never a per-item loop); preflight denials merge beside the native
/// per-item outcomes so callers can keep failed items selected for truthful
/// retry. Source rows and bytes are never mutated.
class DirectMediaLibraryBatchActionsCoordinator {
  DirectMediaLibraryBatchActionsCoordinator({
    required DirectParentMessageLoader loadParentMessage,
    required MediaAttachmentRepository mediaAttachmentRepo,
    required ReceivedMediaEgressService egressService,
    DirectMediaLaneQualifier qualifier = defaultDirectMediaLaneQualifier,
    String Function() requestIdFactory = _defaultEgressRequestId,
    String Function(String storedPath) resolveStoredPath =
        MediaFileManager.resolveStoredPathSync,
    // Sync existence probe: shared with the widget-test fake-async seam of
    // plan 231.
    bool Function(String resolvedPath) fileExists = _defaultFileExists,
  }) : _loadParentMessage = loadParentMessage,
       _mediaAttachmentRepo = mediaAttachmentRepo,
       _egressService = egressService,
       _qualifier = qualifier,
       _requestIdFactory = requestIdFactory,
       _resolveStoredPath = resolveStoredPath,
       _fileExists = fileExists;

  final DirectParentMessageLoader _loadParentMessage;
  final MediaAttachmentRepository _mediaAttachmentRepo;
  final ReceivedMediaEgressService _egressService;
  final DirectMediaLaneQualifier _qualifier;
  final String Function() _requestIdFactory;
  final String Function(String storedPath) _resolveStoredPath;
  final bool Function(String resolvedPath) _fileExists;

  Future<DirectMediaLibraryBatchResult> performBatchEgress({
    required List<DirectReceivedMediaActionIdentity> identities,
    required MediaEgressDestination destination,
  }) async {
    // Dedupe by the complete stable identity while preserving dispatch order.
    // An attachment-id collision from another parent must still be evaluated
    // and fail its exact-row check; it may not be silently collapsed into the
    // first identity. Refuse an empty or over-cap batch before any reload or
    // native call.
    final unique =
        <
          DirectReceivedMediaActionIdentity,
          DirectReceivedMediaActionIdentity
        >{};
    for (final identity in identities) {
      unique.putIfAbsent(identity, () => identity);
    }
    if (unique.isEmpty || unique.length > kMaxMediaEgressItems) {
      throw ArgumentError.value(
        unique.length,
        'identities',
        'batch size must be 1..$kMaxMediaEgressItems',
      );
    }

    final decisions =
        <DirectReceivedMediaActionIdentity, DirectMediaCurrentRowDecision>{};
    final candidates = <ReceivedMediaEgressCandidate>[];
    for (final identity in unique.values) {
      final decision = await qualifyCurrentDirectMediaRow(
        identity: identity,
        loadParentMessage: _loadParentMessage,
        mediaAttachmentRepo: _mediaAttachmentRepo,
        qualifier: _qualifier,
        resolveStoredPath: _resolveStoredPath,
        fileExists: _fileExists,
      );
      decisions[identity] = decision;
      if (decision.isQualified) candidates.add(decision.candidate);
    }

    MediaEgressResult? egressResult;
    var nativeById = const <String, MediaEgressItemResult>{};
    if (candidates.isNotEmpty) {
      egressResult = await _egressService.perform(
        requestId: _requestIdFactory(),
        destination: destination,
        selection: candidates,
      );
      nativeById = {
        for (final item in egressResult.items) item.attachmentId: item,
      };
    }
    // Share is presented as one OS sheet: its success is aggregate, so every
    // qualified candidate succeeds exactly when the sheet was presented.
    final sharePresented =
        destination == MediaEgressDestination.share &&
        egressResult?.outcome == MediaEgressOutcome.presented;

    final items = <DirectMediaLibraryBatchItemOutcome>[];
    for (final identity in unique.values) {
      final decision = decisions[identity]!;
      if (!decision.isQualified) {
        items.add(
          DirectMediaLibraryBatchItemOutcome(
            attachmentId: identity.attachmentId,
            succeeded: false,
            denial: decision.denial,
          ),
        );
        continue;
      }
      if (destination == MediaEgressDestination.share) {
        items.add(
          DirectMediaLibraryBatchItemOutcome(
            attachmentId: identity.attachmentId,
            succeeded: sharePresented,
          ),
        );
        continue;
      }
      final native = nativeById[identity.attachmentId];
      final itemOutcome =
          native?.outcome ?? MediaEgressItemOutcome.platformFailure;
      items.add(
        DirectMediaLibraryBatchItemOutcome(
          attachmentId: identity.attachmentId,
          succeeded: itemOutcome == MediaEgressItemOutcome.saved,
          itemOutcome: itemOutcome,
        ),
      );
    }
    return DirectMediaLibraryBatchResult(
      items: items,
      egressResult: egressResult,
    );
  }
}
