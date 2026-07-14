import 'dart:io';

import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/received_media_egress.dart';
import 'package:flutter_app/core/media/received_media_egress_service.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:uuid/uuid.dart';

import 'private_media_action_eligibility.dart';

/// 231: the ONLY production call site of [ReceivedMediaEgressService.perform].
///
/// UI surfaces (bubble long-press sheet, typed viewer) hold nothing but a
/// stable [DirectReceivedMediaActionIdentity]; immediately before any
/// irreversible egress this controller reloads the current parent message and
/// the current [MediaOwnerLane.direct] attachment row, applies a fail-closed
/// lane qualification, and delegates exactly one current-row candidate to the
/// plan-227 service. Viewer/caption/path metadata is presentation state and
/// never egress authority. No P2P, bridge, relay, send/delete-delivery, or
/// report dependency exists here — Delete for Me and Reply stay on their
/// existing message-level seams.

/// Stable identity of one received direct-chat attachment. Deliberately NOT a
/// path/MIME/protection snapshot: those are reloaded from durable state at
/// dispatch time.
class DirectReceivedMediaActionIdentity {
  const DirectReceivedMediaActionIdentity({
    required this.messageId,
    required this.attachmentId,
  });

  final String messageId;
  final String attachmentId;

  @override
  bool operator ==(Object other) =>
      other is DirectReceivedMediaActionIdentity &&
      other.messageId == messageId &&
      other.attachmentId == attachmentId;

  @override
  int get hashCode => Object.hash(messageId, attachmentId);
}

/// Typed reason a Save/Share dispatch was denied WITHOUT any egress-service
/// call. Each ineligible current-row state is distinguished at this lane
/// boundary instead of being deferred to the native layer.
enum DirectMediaEgressDenial {
  /// The parent message no longer exists locally.
  parentNotFound,

  /// The parent message is a deletion tombstone.
  parentDeleted,

  /// The parent message is not an incoming message.
  parentNotIncoming,

  /// No current direct-lane row exists for the exact attachment ID.
  attachmentNotCurrent,

  /// A lookup returned a row that is not direct-owned (unresolved/legacy or
  /// another lane) — fails closed even if the query should have filtered it.
  wrongOwner,

  /// The parent/attachment returned by a lookup does not match the stable
  /// identity that the caller requested.
  staleIdentity,

  /// The current row is not `done` (pending/downloading/evicted/failed/...).
  notDownloaded,

  /// The current row is quarantined (`integrity_failed`).
  integrityFailed,

  /// The current row has no stored path or the bytes are gone.
  fileMissing,

  /// The lane qualifier reported the item expired.
  expired,

  /// The lane qualifier reported the item protected.
  protected,

  /// The lane qualifier produced no decision — fail closed.
  policyUnavailable,
}

/// Current-row lane qualification. Plan 231 freezes this fail-closed seam;
/// durable private-media (expiry/protection) policy and storage are plan 234's
/// to supply — absence of a decision denies egress.
enum DirectMediaLaneQualification { eligible, expired, protected }

typedef DirectMediaLaneQualifier =
    Future<DirectMediaLaneQualification?> Function(
      ConversationMessage parent,
      MediaAttachment current,
    );

/// Default direct-lane policy backed by the current durable direct-private
/// parent/attachment decision. Ordinary media preserves plan-231 behavior;
/// every private or unsupported mode is denied before native egress.
Future<DirectMediaLaneQualification?> defaultDirectMediaLaneQualifier(
  ConversationMessage parent,
  MediaAttachment current,
) async {
  final decision = DirectPrivateMediaActionEligibility.evaluate(
    parent: parent,
    attachment: current,
    expectedMessageId: parent.id,
    expectedAttachmentId: current.id,
  );
  return switch (decision.reason) {
    DirectPrivateMediaEligibilityReason.ordinary =>
      DirectMediaLaneQualification.eligible,
    DirectPrivateMediaEligibilityReason.privateTerminal =>
      DirectMediaLaneQualification.expired,
    DirectPrivateMediaEligibilityReason.privateAvailable ||
    DirectPrivateMediaEligibilityReason.unsupported =>
      DirectMediaLaneQualification.protected,
    _ => null,
  };
}

typedef DirectParentMessageLoader =
    Future<ConversationMessage?> Function(String messageId);

typedef DirectPrivateMediaActionDecisionLoader =
    Future<DirectPrivateMediaActionDecision> Function(
      DirectReceivedMediaActionIdentity identity,
    );

/// Settled outcome of one egress dispatch: either a typed lane denial (zero
/// service calls) or the untouched typed result of exactly one service call.
class DirectReceivedMediaEgressOutcome {
  const DirectReceivedMediaEgressOutcome.denied(
    DirectMediaEgressDenial this.denial,
  ) : result = null;

  const DirectReceivedMediaEgressOutcome.performed(
    MediaEgressResult this.result,
  ) : denial = null;

  final DirectMediaEgressDenial? denial;
  final MediaEgressResult? result;

  bool get wasDenied => denial != null;
}

/// Local, persisted metadata for the Info surface. Never carries encryption
/// key/nonce material or a raw path.
class DirectReceivedMediaInfo {
  const DirectReceivedMediaInfo({
    required this.isIncoming,
    required this.timestamp,
    required this.mime,
    required this.mediaType,
    required this.sizeBytes,
    required this.downloadStatus,
    this.width,
    this.height,
    this.durationMs,
    this.privateInfo,
  });

  final bool isIncoming;

  /// Owning message ISO-8601 timestamp.
  final String timestamp;

  final String mime;
  final String mediaType;
  final int sizeBytes;
  final String downloadStatus;
  final int? width;
  final int? height;
  final int? durationMs;
  final DirectPrivateMediaSafeInfo? privateInfo;

  bool get isPrivacyMinimized => privateInfo != null;

  bool get isDownloaded => downloadStatus == kMediaDownloadStatusDone;

  bool get isIntegrityFailed =>
      downloadStatus == kMediaDownloadStatusIntegrityFailed;
}

String _defaultEgressRequestId() => const Uuid().v4();

bool _defaultFileExists(String resolvedPath) => File(resolvedPath).existsSync();

/// 233: the settled decision for ONE current direct row — either a typed
/// plan-231 denial or a qualified egress candidate built from the RELOADED
/// row (never a caller snapshot).
class DirectMediaCurrentRowDecision {
  const DirectMediaCurrentRowDecision.denied(
    DirectMediaEgressDenial this.denial,
  ) : parent = null,
      current = null,
      storedPath = null;

  const DirectMediaCurrentRowDecision.qualified({
    required ConversationMessage this.parent,
    required MediaAttachment this.current,
    required String this.storedPath,
  }) : denial = null;

  final DirectMediaEgressDenial? denial;
  final ConversationMessage? parent;
  final MediaAttachment? current;
  final String? storedPath;

  bool get isQualified => denial == null;

  ReceivedMediaEgressCandidate get candidate => ReceivedMediaEgressCandidate(
    attachmentId: current!.id,
    storedPath: storedPath!,
    mime: current!.mime,
  );
}

/// Plan 231's current-row candidate qualification, extracted (233) so the
/// single-item controller and the shared-media batch coordinator apply ONE
/// fail-closed policy. Reloads the parent message and the current
/// [MediaOwnerLane.direct] attachment row immediately before any
/// irreversible egress; viewer/library path/MIME snapshots are never egress
/// authority.
Future<DirectMediaCurrentRowDecision> qualifyCurrentDirectMediaRow({
  required DirectReceivedMediaActionIdentity identity,
  required DirectParentMessageLoader loadParentMessage,
  required MediaAttachmentRepository mediaAttachmentRepo,
  DirectMediaLaneQualifier qualifier = defaultDirectMediaLaneQualifier,
  String Function(String storedPath) resolveStoredPath =
      MediaFileManager.resolveStoredPathSync,
  bool Function(String resolvedPath) fileExists = _defaultFileExists,
}) async {
  final parent = await loadParentMessage(identity.messageId);
  if (parent == null) {
    return const DirectMediaCurrentRowDecision.denied(
      DirectMediaEgressDenial.parentNotFound,
    );
  }
  if (parent.id != identity.messageId) {
    return const DirectMediaCurrentRowDecision.denied(
      DirectMediaEgressDenial.staleIdentity,
    );
  }
  if (parent.isDeleted) {
    return const DirectMediaCurrentRowDecision.denied(
      DirectMediaEgressDenial.parentDeleted,
    );
  }
  if (!parent.isIncoming) {
    return const DirectMediaCurrentRowDecision.denied(
      DirectMediaEgressDenial.parentNotIncoming,
    );
  }

  final rows = await mediaAttachmentRepo.getAttachmentsForMessage(
    identity.messageId,
    owner: MediaOwnerLane.direct,
  );
  MediaAttachment? current;
  for (final row in rows) {
    if (row.id == identity.attachmentId) {
      current = row;
      break;
    }
  }
  if (current == null) {
    return const DirectMediaCurrentRowDecision.denied(
      DirectMediaEgressDenial.attachmentNotCurrent,
    );
  }
  // The query is owner-scoped, but a returned row is re-verified — a
  // legacy/misbehaving lookup must not launder an unresolved or foreign
  // lane row into an egress.
  if (current.ownerLane != MediaOwnerLane.direct) {
    return const DirectMediaCurrentRowDecision.denied(
      DirectMediaEgressDenial.wrongOwner,
    );
  }
  if (current.messageId != identity.messageId ||
      current.id != identity.attachmentId) {
    return const DirectMediaCurrentRowDecision.denied(
      DirectMediaEgressDenial.staleIdentity,
    );
  }

  // The central durable parent/attachment policy is mandatory. The legacy
  // injectable qualifier below may only further restrict an ordinary row; it
  // can never authorize private, terminal, hidden, corrupt, or stale state.
  // Evaluate before status/path probing so protected metadata is not touched
  // merely to discover a privacy denial.
  final centralDecision = DirectPrivateMediaActionEligibility.evaluate(
    parent: parent,
    attachment: current,
    expectedMessageId: identity.messageId,
    expectedAttachmentId: identity.attachmentId,
  );
  if (!centralDecision.isOrdinary) {
    return DirectMediaCurrentRowDecision.denied(
      switch (centralDecision.reason) {
        DirectPrivateMediaEligibilityReason.privateTerminal =>
          DirectMediaEgressDenial.expired,
        DirectPrivateMediaEligibilityReason.privateAvailable ||
        DirectPrivateMediaEligibilityReason.unsupported =>
          DirectMediaEgressDenial.protected,
        DirectPrivateMediaEligibilityReason.wrongOwner =>
          DirectMediaEgressDenial.wrongOwner,
        DirectPrivateMediaEligibilityReason.staleIdentity =>
          DirectMediaEgressDenial.staleIdentity,
        DirectPrivateMediaEligibilityReason.integrityFailed =>
          DirectMediaEgressDenial.integrityFailed,
        _ => DirectMediaEgressDenial.policyUnavailable,
      },
    );
  }
  if (current.downloadStatus == kMediaDownloadStatusIntegrityFailed) {
    return const DirectMediaCurrentRowDecision.denied(
      DirectMediaEgressDenial.integrityFailed,
    );
  }
  if (current.downloadStatus != kMediaDownloadStatusDone) {
    return const DirectMediaCurrentRowDecision.denied(
      DirectMediaEgressDenial.notDownloaded,
    );
  }
  final storedPath = current.localPath;
  if (storedPath == null || storedPath.isEmpty) {
    return const DirectMediaCurrentRowDecision.denied(
      DirectMediaEgressDenial.fileMissing,
    );
  }
  if (!fileExists(resolveStoredPath(storedPath))) {
    return const DirectMediaCurrentRowDecision.denied(
      DirectMediaEgressDenial.fileMissing,
    );
  }

  final qualification = await qualifier(parent, current);
  switch (qualification) {
    case null:
      return const DirectMediaCurrentRowDecision.denied(
        DirectMediaEgressDenial.policyUnavailable,
      );
    case DirectMediaLaneQualification.expired:
      return const DirectMediaCurrentRowDecision.denied(
        DirectMediaEgressDenial.expired,
      );
    case DirectMediaLaneQualification.protected:
      return const DirectMediaCurrentRowDecision.denied(
        DirectMediaEgressDenial.protected,
      );
    case DirectMediaLaneQualification.eligible:
      return DirectMediaCurrentRowDecision.qualified(
        parent: parent,
        current: current,
        storedPath: storedPath,
      );
  }
}

class ReceivedMediaActionController {
  ReceivedMediaActionController({
    required DirectParentMessageLoader loadParentMessage,
    required MediaAttachmentRepository mediaAttachmentRepo,
    required ReceivedMediaEgressService egressService,
    DirectMediaLaneQualifier qualifier = defaultDirectMediaLaneQualifier,
    String Function() requestIdFactory = _defaultEgressRequestId,
    String Function(String storedPath) resolveStoredPath =
        MediaFileManager.resolveStoredPathSync,
    // Sync existence probe: this controller also runs inside widget-test
    // fake-async zones where awaited real dart:io never completes.
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

  /// Reloads and qualifies the CURRENT direct parent/attachment, then calls
  /// [ReceivedMediaEgressService.perform] exactly once with one current-row
  /// candidate. Any ineligible state yields a typed denial with zero service
  /// calls; the source row/bytes are never mutated.
  Future<DirectReceivedMediaEgressOutcome> performEgress({
    required DirectReceivedMediaActionIdentity identity,
    required MediaEgressDestination destination,
  }) async {
    final decision = await qualifyCurrentDirectMediaRow(
      identity: identity,
      loadParentMessage: _loadParentMessage,
      mediaAttachmentRepo: _mediaAttachmentRepo,
      qualifier: _qualifier,
      resolveStoredPath: _resolveStoredPath,
      fileExists: _fileExists,
    );
    if (!decision.isQualified) {
      return DirectReceivedMediaEgressOutcome.denied(decision.denial!);
    }

    final result = await _egressService.perform(
      requestId: _requestIdFactory(),
      destination: destination,
      selection: [decision.candidate],
    );
    return DirectReceivedMediaEgressOutcome.performed(result);
  }

  /// Reloads the exact current direct parent/attachment and returns the same
  /// typed decision used by dispatch boundaries. Presentation adapters use
  /// this immediately before entering an ordinary viewer; cached message or
  /// library rows never authorize navigation.
  Future<DirectPrivateMediaActionDecision> loadActionDecision(
    DirectReceivedMediaActionIdentity identity,
  ) async {
    final parent = await _loadParentMessage(identity.messageId);
    MediaAttachment? current;
    if (parent != null && parent.id == identity.messageId) {
      final rows = await _mediaAttachmentRepo.getAttachmentsForMessage(
        identity.messageId,
        owner: MediaOwnerLane.direct,
      );
      for (final row in rows) {
        if (row.id == identity.attachmentId) {
          current = row;
          break;
        }
      }
    }
    return DirectPrivateMediaActionEligibility.evaluate(
      parent: parent,
      attachment: current,
      expectedMessageId: identity.messageId,
      expectedAttachmentId: identity.attachmentId,
      requireIncoming: false,
    );
  }

  /// Current local metadata for the Info surface — persisted rows only, no
  /// transport access. Returns null when the exact direct-owned current row
  /// (or its live parent) no longer exists.
  Future<DirectReceivedMediaInfo?> loadInfo(
    DirectReceivedMediaActionIdentity identity,
  ) async {
    final parent = await _loadParentMessage(identity.messageId);
    if (parent == null || parent.isDeleted) return null;

    final rows = await _mediaAttachmentRepo.getAttachmentsForMessage(
      identity.messageId,
      owner: MediaOwnerLane.direct,
    );
    MediaAttachment? current;
    for (final row in rows) {
      if (row.id == identity.attachmentId) {
        current = row;
        break;
      }
    }
    final mayOmitCleanedAttachment =
        parent.privateMediaPolicy.requiresRedaction &&
        parent.privateMediaState.isTerminal;
    final decision = DirectPrivateMediaActionEligibility.evaluate(
      parent: parent,
      attachment: current,
      expectedMessageId: identity.messageId,
      expectedAttachmentId: identity.attachmentId,
      attachmentRequired: !mayOmitCleanedAttachment,
    );
    if (decision.isPrivateOrUnsupported &&
        decision.allows(DirectPrivateMediaAction.info)) {
      return DirectReceivedMediaInfo(
        isIncoming: parent.isIncoming,
        timestamp: parent.timestamp,
        mime: '',
        mediaType: '',
        sizeBytes: 0,
        downloadStatus: '',
        privateInfo: decision.safeInfo,
      );
    }
    if (!decision.isOrdinary || current == null) return null;
    return DirectReceivedMediaInfo(
      isIncoming: parent.isIncoming,
      timestamp: parent.timestamp,
      mime: current.mime,
      mediaType: current.mediaType,
      sizeBytes: current.size,
      downloadStatus: current.downloadStatus,
      width: current.width,
      height: current.height,
      durationMs: current.durationMs,
    );
  }
}
