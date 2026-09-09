import 'package:flutter_app/core/diagnostics/app_diagnostics.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:uuid/uuid.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/database/direct_media_blob_custody.dart'
    show
        DirectMediaBlobCustodyDirection,
        DirectMediaBlobCustodyRow,
        DirectMediaBlobCustodyState;
import 'package:flutter_app/core/database/helpers/direct_inbox_custody_outbox_db_helpers.dart'
    show isExactV2DirectChatInitialEnvelope;
import 'package:flutter_app/core/database/helpers/media_attachments_db_helpers.dart'
    show
        DirectMediaFanoutStageAuthority,
        DirectMediaFanoutTargetBinding,
        OutgoingDirectMediaCaptionEditLane;
import 'package:flutter_app/core/database/outgoing_transport_mutation.dart';
import 'package:flutter_app/core/debug/transport_metrics.dart';
import 'package:flutter_app/core/local_discovery/lan_ack.dart';
import 'package:flutter_app/core/media/direct_media_blob_custody.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/direct_media_custody_intent.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_file_path_convention.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/outgoing_direct_private_mutation_coordinator.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/chat_console_logger.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/utils/text_sanitizer.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_inbox_custody_outbox_entry.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_reaction_inbox_custody_outbox_entry.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/message_payload.dart';
import 'package:flutter_app/core/database/direct_event_fanout_contract.dart';
import 'package:flutter_app/features/conversation/application/direct_event_fanout_coordinator.dart';
import 'package:flutter_app/features/conversation/application/drain_direct_inbox_custody_outbox_use_case.dart';
import 'package:flutter_app/features/conversation/application/drain_direct_reaction_inbox_custody_outbox_use_case.dart';
import 'package:flutter_app/features/conversation/application/outgoing_direct_private_transport_settlement.dart';
import 'package:flutter_app/features/conversation/application/outgoing_live_deadline.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';

/// Interactive send budget for local WiFi attempts.
const Duration interactiveLocalBudget = Duration(milliseconds: 1500);

/// Interactive send budget for the overall direct send path.
const Duration interactiveDirectBudget = Duration(seconds: 2);

/// Backwards-compatible name for the ordinary outgoing live-leg deadline.
const Duration interactiveDirectAggregateBudget = outgoingLiveBudget;

/// Interactive send budget for the inbox store fallback path.
const Duration interactiveInboxBudget = Duration(seconds: 3);

/// Presence-independent durability hedge for peers that appear live or local.
///
/// Measured from the existing send-entry T0. Unknown peers start durable inbox
/// custody immediately after attempt staging; structurally reachable peers wait
/// only for the remainder of this budget while authenticated live work races.
const Duration kConnectedPeerInboxHedgeBudget = Duration(milliseconds: 2500);

/// FDC-08: tight bound on the presence-hint lookup so it stays OFF the
/// send-critical path. In steady state it is a 10–15s-cached read (≈0ms); a cold
/// lookup that exceeds this degrades to `RelayPresence.unknown` (today's full
/// concurrent race) while the underlying lookup still completes and warms the
/// cache for the next send. Consulted ONLY on the not-live-reachable path.
const Duration _presenceHintBudget = Duration(milliseconds: 400);

/// Shared single-attempt cap for the live relay recovery owned by introduction
/// outbound delivery and delete-for-everyone. The conversation send path has no
/// serial probe step: FDC-02 owns its in-race relay-live leg, and an all-fail
/// race proceeds to durable inbox custody.
const int relayProbeSendAttempts = 1;

// FDC-03: the NET-REL-05 P1/P4 `kLowConfidenceWindow` (30s prior-attempt recency
// gate) is RETIRED. The concurrent durable inbox now fires for ALL unknown-
// presence sends (see the `unknownPresence` gate in `sendChatMessage`), not only
// recently-failed peers, so the recency window no longer gates anything.

/// FDC-02 §6.2a / §12 (libp2p DefaultDialRanker `RelayDelay`): the relay-LIVE
/// leg is penalized by this stagger so a viable LAN/direct leg that acks first
/// WINS and the relay-live leg is never started (suppress-on-early-win), instead
/// of relay riding the direct leg with no handicap. A warmed `/p2p-circuit` then
/// races-but-loses to a 30ms LAN hop (§6.1 by priority, not suppression).
/// Ordering invariant (TC-02-08): kRelayLegStagger > kPublicAddrTail >
/// kPrivateAddrTail.
const Duration kRelayLegStagger = Duration(milliseconds: 500);

/// FDC-02 §12 Happy-Eyeballs per-address tails. Pinned here only for the ordering
/// invariant; their PER-ADDRESS application inside a single dial is the Go host's
/// `DefaultDialRanker` (FDC-11, device-only). FDC-02 implements only the
/// leg-granularity [kRelayLegStagger] analog in Dart.
const Duration kPublicAddrTail = Duration(milliseconds: 250);
const Duration kPrivateAddrTail = Duration(milliseconds: 30);

/// FDC-02 §6.2b: a circuit-v2 LIVE relay socket is "limited" (~128KB/direction
/// before reset). Any payload whose ENCRYPTED ENVELOPE UTF-8 byte length exceeds
/// this ceiling NEVER traverses the live relay leg: it goes LAN-live,
/// direct-live, or the durable inbox (relay-INBOX) only. Headroom under the
/// 128KB cap. (R5 / TC-339-01/03/04/05.)
const int kLiveRelayMaxPayloadBytes = 96 * 1024;

/// Backwards-compatible names for the two capped pre-send phases.
const Duration kDirectDiscoverBudget = outgoingDiscoverPhaseCap;
const Duration kDirectDialBudget = outgoingDialPhaseCap;

/// Legacy constant retained for callers/tests that describe the old ladder.
/// R3 committed sends no longer use this cap; they receive the exact remaining
/// native allocation while preserving the committed-ACK reserve.
const Duration kDirectSendBudget = Duration(milliseconds: 1500);

/// One send-scoped, typed durability operation shared by the delayed hedge and
/// both terminal non-proof funnels.
///
/// Starting and cancellation claim state synchronously. Cancellation only
/// disarms work that has not begun; an operation already in flight always
/// completes. A fresh retry is available exactly once, and only after the
/// completed initial operation produced [InboxStoreStatus.failed].
final class _SendScopedInboxHedge {
  _SendScopedInboxHedge(this._operation);

  static const _canceledOutcome = InboxStoreOutcome(
    status: InboxStoreStatus.failed,
    errorCode: 'HEDGE_CANCELED',
  );

  final Future<InboxStoreOutcome> Function() _operation;

  Timer? _timer;
  Future<InboxStoreOutcome>? _initialFuture;
  Future<InboxStoreOutcome>? _retryFuture;
  InboxStoreOutcome? _initialOutcome;
  bool _started = false;
  bool _canceled = false;

  bool get hasStarted => _started;

  void schedule(Duration delay) {
    if (_started || _canceled || _timer != null) return;
    if (delay <= Duration.zero) {
      unawaited(startOrJoin());
      return;
    }
    _timer = Timer(delay, () {
      _timer = null;
      unawaited(startOrJoin());
    });
  }

  Future<InboxStoreOutcome> startOrJoin() {
    final existing = _initialFuture;
    if (existing != null) return existing;

    if (_canceled) {
      _initialOutcome = _canceledOutcome;
      return _initialFuture = Future<InboxStoreOutcome>.value(_canceledOutcome);
    }

    _started = true;
    _timer?.cancel();
    _timer = null;
    final completer = Completer<InboxStoreOutcome>();
    _initialFuture = completer.future;
    unawaited(
      _runOperation().then((outcome) {
        _initialOutcome = outcome;
        completer.complete(outcome);
      }),
    );
    return completer.future;
  }

  Future<InboxStoreOutcome> retryAfterFailure() {
    final initial = _initialOutcome;
    if (!_started || initial?.status != InboxStoreStatus.failed) {
      return Future<InboxStoreOutcome>.value(initial ?? _canceledOutcome);
    }

    final existing = _retryFuture;
    if (existing != null) return existing;
    final completer = Completer<InboxStoreOutcome>();
    _retryFuture = completer.future;
    unawaited(_runOperation().then(completer.complete));
    return completer.future;
  }

  bool cancelIfNotStarted() {
    if (_started || _canceled) return false;
    _canceled = true;
    _timer?.cancel();
    _timer = null;
    _initialOutcome = _canceledOutcome;
    _initialFuture = Future<InboxStoreOutcome>.value(_canceledOutcome);
    return true;
  }

  Future<InboxStoreOutcome> _runOperation() async {
    try {
      return await _operation();
    } catch (error) {
      return InboxStoreOutcome(
        status: InboxStoreStatus.failed,
        errorCode: 'HEDGE_OPERATION_ERROR',
        errorMessage: error.toString(),
      );
    }
  }
}

/// FDC-02 observability seam (C2). Production [P2PService] impls do NOT implement
/// this: the staggered relay-live leg's delivery is an ordinary
/// `sendMessageWithReply`, indistinguishable on the wire from the direct / reuse
/// / probe-tail sends. A host fake implements it so a test can attribute the
/// otherwise-identical circuit send to the relay-LIVE leg specifically — the
/// leg-attributable proof the leg did/did not start, since "sent while only a
/// circuit conn exists" over-counts the direct/reuse/probe sends. Mirrors the
/// existing [ReadinessProofRecorder] capability-interface pattern. Fired only
/// AFTER the suppress-on-early-win guard passes, so a suppressed leg is never
/// counted.
abstract interface class RelayLiveSendObserver {
  void noteRelayLiveSendStart();
}

void _recordSuccessfulSendReadinessProof(
  P2PService p2pService,
  ConversationMessage message,
) {
  // 'inboxed' (relay custody, doc 115) proves transport readiness exactly as
  // the pre-115 'delivered'/'inbox' terminal did: the relay accepted a store.
  if (message.status != 'delivered' && message.status != 'inboxed') {
    return;
  }

  if (p2pService case final ReadinessProofRecorder recorder) {
    final sendPath = switch (message.transport) {
      'local' => 'local',
      'relay' => 'relay',
      'inbox' => 'inbox',
      'reuse' => 'direct',
      _ => 'direct',
    };
    final source = switch (sendPath) {
      'local' => 'chat_send_local',
      'relay' => 'chat_send_relay',
      'inbox' => 'chat_send_inbox',
      _ => 'chat_send_direct',
    };
    recorder.recordSuccessfulSendProof(
      source: source,
      trigger: 'user_action',
      sendPath: sendPath,
    );
  }
}

/// Result of sending a chat message.
enum SendChatMessageResult {
  success,
  nodeNotRunning,
  invalidMessage,
  invalidPrivateMedia,
  encryptionRequired,

  /// 112 G5: an outbound attachment lacks complete blob-encryption
  /// metadata — the media mirror of [encryptionRequired]. Nothing was
  /// persisted or transported.
  mediaEncryptionRequired,
  peerNotFound,
  dialFailed,
  sendFailed,
}

const _uuid = Uuid();

/// 112 G5 fail-closed gate: every outbound 1:1 attachment must be
/// decryptable-with-v1 (key + nonce + whitelisted scheme — the sender
/// always writes the scheme explicitly) and carry the encrypted-blob
/// contentHash. Returns a reason code, or null when the attachments pass.
String? _sanitizeDirectMediaAttachments(List<MediaAttachment>? attachments) {
  if (attachments == null || attachments.isEmpty) {
    return null;
  }
  for (final attachment in attachments) {
    if (attachment.ownerLane != null &&
        attachment.ownerLane != MediaOwnerLane.direct) {
      return 'wrong_media_owner_lane';
    }
    if (!attachment.hasEncryptionMetadata ||
        attachment.encryptionScheme == null) {
      return 'missing_media_encryption_metadata';
    }
    if (attachment.contentHash == null || attachment.contentHash!.isEmpty) {
      return 'missing_media_content_hash';
    }
  }
  return null;
}

final RegExp _directMediaCustodySha256 = RegExp(r'^[0-9a-f]{64}$');
const Set<String> _directMediaCustodyTypes = <String>{
  'image',
  'video',
  'audio',
  'file',
};

/// The two durable parent policies a TOKEN-BEARING media preflight may adopt.
///
/// Ordinary v0 keeps its exact historical shape. 358 additionally admits the
/// authored v1 `disappearing` shape — one allowed duration, lifecycle
/// `available` — but only when the caller's own effective policy is that same
/// exact disappearing policy, so a drifted caller can never retarget a durable
/// parent onto another modality.
bool _isTokenBearingDirectMediaPreflightPolicy(
  ConversationMessage durableParent, {
  required PrivateMediaPolicy expected,
}) {
  if (durableParent.privateMediaPolicy.version == 0 &&
      durableParent.privateMediaMode == PrivateMediaMode.ordinary &&
      durableParent.privateMediaDurationSeconds == null &&
      durableParent.privateMediaState == PrivateMediaLifecycleState.none) {
    return expected.mode == PrivateMediaMode.ordinary;
  }
  return expected.mode == PrivateMediaMode.disappearing &&
      durableParent.privateMediaPolicy == expected &&
      durableParent.privateMediaMode == PrivateMediaMode.disappearing &&
      durableParent.privateMediaDurationSeconds != null &&
      PrivateMediaPolicy.allowedDurationsSeconds.contains(
        durableParent.privateMediaDurationSeconds,
      ) &&
      durableParent.privateMediaState == PrivateMediaLifecycleState.available;
}

bool _isCompleteDirectMediaCustodyCandidate(
  MediaAttachment attachment, {
  required String messageId,
  bool allowPreparedPendingPath = false,
}) {
  final localPath = attachment.localPath?.trim();
  final normalizedPath = localPath?.replaceAll('\\', '/');
  final usesPendingPath =
      normalizedPath?.startsWith('pending_uploads/') == true ||
      normalizedPath?.contains('/pending_uploads/') == true;
  final expectedPendingPath =
      MediaFilePathConvention.relativePathForPendingUpload(
        messageId: messageId,
        attachmentId: attachment.id,
        mime: attachment.mime,
      ).replaceAll('\\', '/');
  return attachment.id.isNotEmpty &&
      attachment.messageId == messageId &&
      attachment.ownerLane == MediaOwnerLane.direct &&
      attachment.mime.trim().isNotEmpty &&
      attachment.size > 0 &&
      _directMediaCustodyTypes.contains(attachment.mediaType) &&
      attachment.mediaType ==
          MediaAttachment.mediaTypeFromMime(attachment.mime) &&
      attachment.downloadStatus == 'done' &&
      attachment.createdAt.trim().isNotEmpty &&
      localPath != null &&
      localPath.isNotEmpty &&
      (!usesPendingPath ||
          (allowPreparedPendingPath &&
              normalizedPath == expectedPendingPath)) &&
      _directMediaCustodySha256.hasMatch(attachment.contentHash ?? '') &&
      (attachment.thumbnailHash == null ||
          _directMediaCustodySha256.hasMatch(attachment.thumbnailHash!)) &&
      (attachment.encryptionKeyBase64?.trim().isNotEmpty ?? false) &&
      (attachment.encryptionNonce?.trim().isNotEmpty ?? false) &&
      attachment.encryptionScheme ==
          kMediaAttachmentEncryptionSchemeBlobAesGcmV1 &&
      (attachment.width == null || attachment.width! >= 0) &&
      (attachment.height == null || attachment.height! >= 0) &&
      (attachment.durationMs == null || attachment.durationMs! >= 0) &&
      (attachment.waveform == null ||
          attachment.waveform!.every(
            (sample) => sample.isFinite && sample >= 0 && sample <= 1,
          ));
}

bool _sameDirectMediaCustodyWaveform(List<double>? left, List<double>? right) {
  if (identical(left, right)) return true;
  if (left == null || right == null || left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

bool _samePreparedDirectMediaStableIdentity(
  MediaAttachment durable,
  MediaAttachment candidate,
) =>
    durable.id == candidate.id &&
    durable.messageId == candidate.messageId &&
    durable.ownerLane == candidate.ownerLane &&
    durable.mime == candidate.mime &&
    durable.size == candidate.size &&
    durable.mediaType == candidate.mediaType &&
    durable.width == candidate.width &&
    durable.height == candidate.height &&
    durable.durationMs == candidate.durationMs &&
    durable.createdAt == candidate.createdAt &&
    _sameDirectMediaCustodyWaveform(durable.waveform, candidate.waveform);

bool _sameCompletedDirectMediaAttempt(
  MediaAttachment durable,
  MediaAttachment candidate,
) =>
    _samePreparedDirectMediaStableIdentity(durable, candidate) &&
    durable.localPath == candidate.localPath &&
    durable.downloadStatus == candidate.downloadStatus &&
    (durable.uploadRetryCount ?? 0) == (candidate.uploadRetryCount ?? 0) &&
    (durable.downloadRetryCount ?? 0) == (candidate.downloadRetryCount ?? 0) &&
    durable.contentHash == candidate.contentHash &&
    durable.thumbnailHash == candidate.thumbnailHash &&
    durable.encryptionKeyBase64 == candidate.encryptionKeyBase64 &&
    durable.encryptionNonce == candidate.encryptionNonce &&
    durable.encryptionScheme == candidate.encryptionScheme;

bool _isExactPreparedDirectMediaPreflightProjection({
  required String messageId,
  required List<MediaAttachment> durable,
  required List<MediaAttachment> candidates,
  required bool allowPreparedPendingPath,
}) {
  if (durable.length != candidates.length) return false;
  final candidatesById = <String, MediaAttachment>{
    for (final candidate in candidates) candidate.id: candidate,
  };
  if (candidatesById.length != candidates.length) return false;

  for (final persisted in durable) {
    final candidate = candidatesById[persisted.id];
    if (candidate == null ||
        !_isCompleteDirectMediaCustodyCandidate(
          candidate,
          messageId: messageId,
          allowPreparedPendingPath: allowPreparedPendingPath,
        )) {
      return false;
    }
    if (persisted.downloadStatus == 'done') {
      if (!_sameCompletedDirectMediaAttempt(persisted, candidate)) return false;
      continue;
    }
    final strictCommitment = candidate.blobCustody;
    final isPublishedStrictGeneration =
        persisted.downloadStatus == 'upload_pending' &&
        candidate.downloadStatus == 'done' &&
        strictCommitment != null &&
        strictCommitment.isValid &&
        strictCommitment.contentHash == persisted.contentHash &&
        persisted.contentHash == candidate.contentHash &&
        persisted.thumbnailHash == candidate.thumbnailHash &&
        persisted.localPath == candidate.localPath &&
        (persisted.uploadRetryCount ?? 0) ==
            (candidate.uploadRetryCount ?? 0) &&
        (persisted.downloadRetryCount ?? 0) ==
            (candidate.downloadRetryCount ?? 0) &&
        persisted.encryptionKeyBase64 == candidate.encryptionKeyBase64 &&
        persisted.encryptionNonce == candidate.encryptionNonce &&
        persisted.encryptionScheme == candidate.encryptionScheme &&
        _samePreparedDirectMediaStableIdentity(persisted, candidate);
    if (isPublishedStrictGeneration) continue;
    final expectedPendingPath =
        MediaFilePathConvention.relativePathForPendingUpload(
          messageId: messageId,
          attachmentId: persisted.id,
          mime: persisted.mime,
        );
    if (persisted.downloadStatus != 'upload_pending' ||
        persisted.localPath != expectedPendingPath ||
        persisted.contentHash != null ||
        persisted.thumbnailHash != null ||
        persisted.encryptionKeyBase64 != null ||
        persisted.encryptionNonce != null ||
        persisted.encryptionScheme != null ||
        !_samePreparedDirectMediaStableIdentity(persisted, candidate)) {
      return false;
    }
  }
  return true;
}

bool _isExactDirectInboxCustodyReplay({
  required DirectInboxCustodyOutboxEntry custody,
  required String messageId,
  required String senderPeerId,
}) {
  final exactIncarnation = RegExp(
    r'^[0-9a-f]{32}$',
  ).hasMatch(custody.incarnationId);
  final exactEnvelope = isExactV2DirectChatInitialEnvelope(
    custody.wireEnvelope,
    messageId: messageId,
    senderPeerId: senderPeerId,
  );
  return exactIncarnation &&
      exactEnvelope &&
      custody.recipientPeerId.trim().isNotEmpty &&
      custody.messageId == messageId;
}

/// 301: best-effort inline thumbnail for a protected PHOTO. Photo means the
/// dual check excludes gif (mirror of the eligibility kind fork below — a bare
/// image-mime predicate would wrongly embed thumbs for protected GIFs, which
/// are representable at this seam). Any failure returns null and the send
/// proceeds without the field.
Future<Uint8List?> _generateProtectedPhotoInlineThumbnail(
  MediaAttachment attachment,
) async {
  final mime = attachment.mime.toLowerCase();
  final mediaType = attachment.mediaType.toLowerCase();
  if (mime == 'image/gif' || mediaType == 'gif') return null;
  if (!(mime.startsWith('image/') || mediaType == 'image')) return null;
  final localPath = attachment.localPath;
  if (localPath == null || localPath.isEmpty) return null;
  return ImageProcessor.generateInlineThumbnailBytes(
    inputPath: MediaFileManager.resolveStoredPathSync(localPath),
  );
}

PrivateMediaEligibility _privateMediaEligibilityForSend({
  required String text,
  required String action,
  required bool isForwarded,
  required List<MediaAttachment>? attachments,
}) {
  var kind = PrivateMediaAttachmentKind.unknown;
  if (attachments != null && attachments.length == 1) {
    final attachment = attachments.single;
    final mime = attachment.mime.toLowerCase();
    final mediaType = attachment.mediaType.toLowerCase();
    if (mime == 'image/gif' || mediaType == 'gif') {
      kind = PrivateMediaAttachmentKind.gif;
    } else if (mime.startsWith('image/') || mediaType == 'image') {
      kind = PrivateMediaAttachmentKind.image;
    } else if (mime.startsWith('video/') || mediaType == 'video') {
      kind = PrivateMediaAttachmentKind.video;
    } else if (mime.startsWith('audio/') || mediaType == 'audio') {
      kind = PrivateMediaAttachmentKind.audio;
    } else if (mime.isNotEmpty || mediaType == 'file') {
      kind = PrivateMediaAttachmentKind.file;
    }
  }
  return PrivateMediaEligibility(
    attachmentCount: attachments?.length ?? 0,
    attachmentKind: kind,
    hasTextOrCaption: text.trim().isNotEmpty,
    isEdit: action == MessagePayload.actionEdit,
    isForward: isForwarded,
  );
}

/// 362: the caller-proven authority for one direct linked-media v108 fanout.
///
/// Provided ONLY by a producer/retry lane that already owns a complete STORED
/// v114 linked generation (every snapshot target's rows in [targetRows]). Once
/// supplied, the send may settle exclusively through the plural fanout stage —
/// any shape/authority mismatch fails closed and never demotes to the
/// single-target v108 stage.
final class DirectLinkedMediaFanoutTargetAuthority {
  const DirectLinkedMediaFanoutTargetAuthority({
    required this.peerId,
    required this.mlKemPublicKey,
  });

  final String peerId;
  final String mlKemPublicKey;
}

final class DirectLinkedMediaFanoutContext {
  factory DirectLinkedMediaFanoutContext({
    required String contactAccountPeerId,
    required DirectContactFanoutSnapshot snapshot,
    required Map<String, List<DirectMediaBlobCustodyRow>> targetRows,
  }) => DirectLinkedMediaFanoutContext._(
    contactAccountPeerId: contactAccountPeerId,
    authority: DirectMediaFanoutStageAuthority.currentRosterSnapshot,
    snapshot: snapshot,
    targets: snapshot.targets
        .map(
          (target) => DirectLinkedMediaFanoutTargetAuthority(
            peerId: target.peerId,
            mlKemPublicKey: target.mlKemPublicKey,
          ),
        )
        .toList(growable: false),
    targetRows: targetRows,
  );

  const DirectLinkedMediaFanoutContext._({
    required this.contactAccountPeerId,
    required this.authority,
    required this.snapshot,
    required this.targets,
    required this.targetRows,
  });

  /// Reconstructs restart authority solely from complete persisted v114 rows.
  /// The logical account target, when present, is the canonical witness;
  /// remaining physical peers are stable lexical order.
  static DirectLinkedMediaFanoutContext? fromPersistedV114Survivors({
    required String contactAccountPeerId,
    required Map<String, List<DirectMediaBlobCustodyRow>> targetRows,
  }) {
    if (contactAccountPeerId.trim().isEmpty || targetRows.isEmpty) return null;
    final targetsByPeer = <String, DirectLinkedMediaFanoutTargetAuthority>{};
    for (final entry in targetRows.entries) {
      final peerId = entry.key;
      final rows = entry.value;
      if (peerId.trim().isEmpty || rows.isEmpty) return null;
      final key = rows.first.recipientMlKemPublicKey?.trim();
      if (key == null ||
          key.isEmpty ||
          rows.any(
            (row) =>
                !row.isLinkedFanoutRow ||
                row.contactAccountPeerId != contactAccountPeerId ||
                row.recipientPeerId != peerId ||
                row.recipientMlKemPublicKey != key ||
                row.direction != DirectMediaBlobCustodyDirection.outgoing ||
                row.state != DirectMediaBlobCustodyState.outgoingStored,
          )) {
        return null;
      }
      targetsByPeer[peerId] = DirectLinkedMediaFanoutTargetAuthority(
        peerId: peerId,
        mlKemPublicKey: key,
      );
    }
    final orderedPeerIds = targetsByPeer.keys.toList()..sort();
    if (orderedPeerIds.remove(contactAccountPeerId)) {
      orderedPeerIds.insert(0, contactAccountPeerId);
    }
    return DirectLinkedMediaFanoutContext._(
      contactAccountPeerId: contactAccountPeerId,
      authority: DirectMediaFanoutStageAuthority.persistedV114Survivors,
      snapshot: null,
      targets: orderedPeerIds
          .map((peerId) => targetsByPeer[peerId]!)
          .toList(growable: false),
      targetRows: Map<String, List<DirectMediaBlobCustodyRow>>.unmodifiable({
        for (final peerId in orderedPeerIds)
          peerId: List<DirectMediaBlobCustodyRow>.unmodifiable(
            targetRows[peerId]!,
          ),
      }),
    );
  }

  final String contactAccountPeerId;
  final DirectMediaFanoutStageAuthority authority;
  final DirectContactFanoutSnapshot? snapshot;
  final List<DirectLinkedMediaFanoutTargetAuthority> targets;

  /// recipientPeerId -> that target's exact STORED v114 rows.
  final Map<String, List<DirectMediaBlobCustodyRow>> targetRows;
}

/// Caller-owned authority for one initialized private-media linked fanout.
///
/// Private Protected/View-Once initials deliberately do not mint a v110
/// intent. Fresh authoring therefore carries the exact pre-effect roster
/// snapshot into private Barrier B, while restart reconstructs authority only
/// from the complete persisted v114 survivor set.
final class DirectPrivateMediaFanoutContext {
  factory DirectPrivateMediaFanoutContext({
    required String contactAccountPeerId,
    required DirectContactFanoutSnapshot snapshot,
    required Map<String, List<DirectMediaBlobCustodyRow>> targetRows,
  }) => DirectPrivateMediaFanoutContext._(
    contactAccountPeerId: contactAccountPeerId,
    authority: DirectPrivateMediaFanoutStageAuthority.currentRosterSnapshot,
    snapshot: snapshot,
    targets: snapshot.targets
        .map(
          (target) => DirectLinkedMediaFanoutTargetAuthority(
            peerId: target.peerId,
            mlKemPublicKey: target.mlKemPublicKey,
          ),
        )
        .toList(growable: false),
    targetRows: targetRows,
  );

  const DirectPrivateMediaFanoutContext._({
    required this.contactAccountPeerId,
    required this.authority,
    required this.snapshot,
    required this.targets,
    required this.targetRows,
  });

  static DirectPrivateMediaFanoutContext? fromPersistedV114Survivors({
    required String contactAccountPeerId,
    required Map<String, List<DirectMediaBlobCustodyRow>> targetRows,
  }) {
    final ordinary = DirectLinkedMediaFanoutContext.fromPersistedV114Survivors(
      contactAccountPeerId: contactAccountPeerId,
      targetRows: targetRows,
    );
    if (ordinary == null) return null;
    return DirectPrivateMediaFanoutContext._(
      contactAccountPeerId: ordinary.contactAccountPeerId,
      authority: DirectPrivateMediaFanoutStageAuthority.persistedV114Survivors,
      snapshot: null,
      targets: ordinary.targets,
      targetRows: ordinary.targetRows,
    );
  }

  final String contactAccountPeerId;
  final DirectPrivateMediaFanoutStageAuthority authority;
  final DirectContactFanoutSnapshot? snapshot;
  final List<DirectLinkedMediaFanoutTargetAuthority> targets;
  final Map<String, List<DirectMediaBlobCustodyRow>> targetRows;
}

/// Sends a chat message to a contact via P2P and persists it locally.
///
/// 1. Validates text is non-empty
/// 2. Checks P2P node is running
/// 3. Builds MessagePayload with UUID
/// 4. Serializes to a v2 encrypted JSON envelope
/// 5. Atomically stages the parent/envelope (and ordinary media projection)
/// 6. Reuses an existing connection, races local WiFi with direct relay send,
///    and probes the relay only when discoverability is stale
/// 7. Atomically settles the attempt-owned transport columns
///
/// A live send that writes to the peer but does not receive an ACK attempts an
/// immediate durable inbox handoff. If the inbox handoff also fails, the
/// message is kept as truthful local `sent` state with the wire envelope
/// retained for later retry.
///
/// The wireEnvelope persist at step 5 ensures that if the app crashes during
/// the transport race (step 6), Section 1's PendingMessageRetrier can replay
/// the message without re-serializing or re-encrypting.
///
/// Returns (result, ConversationMessage?) — message is non-null on success or failure (persisted).
Future<(SendChatMessageResult, ConversationMessage?)> sendChatMessage({
  required P2PService p2pService,
  required MessageRepository messageRepo,
  required String targetPeerId,
  required String text,
  required String senderPeerId,
  required String senderUsername,
  String action = MessagePayload.actionSend,
  String? editedAt,
  String? messageId,
  bool preassignedMessageIdIsFresh = false,
  String? timestamp,
  // F8 tier-2: a normal send stamps `dedupKey = its own id` (the default
  // below); one explicit Forward action passes its random operation token so
  // retry/redelivery dedups without coupling later actions to the source.
  String? dedupKey,
  bool isForwarded = false,
  String? createdAt,
  Bridge? bridge,
  String? recipientMlKemPublicKey,
  String? quotedMessageId,
  List<MediaAttachment>? mediaAttachments,
  PrivateMediaPolicy? privateMediaPolicy,
  MediaAttachmentRepository? mediaAttachmentRepo,
  bool emitTimingEvent = true,
  TransportMetrics? transportMetrics,
  StoreInInboxDetailedFn? storeInInboxDetailed,
  StoreInAckCustodyInboxDetailedFn? storeInAckCustodyInboxDetailed,
  StoreInMediaExpiryBoundedInboxDetailedFn?
  storeInMediaExpiryBoundedInboxDetailed,
  void Function(String messageId)? onDirectTextCustodyStaged,
  DirectEventFanoutAuthoring? directEventFanout,
  DirectLinkedMediaFanoutContext? directLinkedMediaFanout,
  DirectPrivateMediaFanoutContext? directPrivateMediaFanout,
}) async {
  final diagnostics = AppDiagnostics.instance;
  return diagnostics.runWithAttempt(
    feature: 'message',
    traceId: messageId == null
        ? null
        : diagnostics.traceForOperation('message:$messageId'),
    body: (traceId) async {
      final diagnosticTimer = Stopwatch()..start();
      diagnostics.record(
        feature: 'message',
        stage: 'preflight',
        outcome: 'started',
        traceId: traceId,
        values: {
          'direction': 'outgoing',
          'hasAttachments': mediaAttachments?.isNotEmpty ?? false,
        },
      );
      try {
        final result = await _sendChatMessageDiagnosed(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: targetPeerId,
          text: text,
          senderPeerId: senderPeerId,
          senderUsername: senderUsername,
          action: action,
          editedAt: editedAt,
          messageId: messageId,
          preassignedMessageIdIsFresh: preassignedMessageIdIsFresh,
          timestamp: timestamp,
          dedupKey: dedupKey,
          isForwarded: isForwarded,
          createdAt: createdAt,
          bridge: bridge,
          recipientMlKemPublicKey: recipientMlKemPublicKey,
          quotedMessageId: quotedMessageId,
          mediaAttachments: mediaAttachments,
          privateMediaPolicy: privateMediaPolicy,
          mediaAttachmentRepo: mediaAttachmentRepo,
          emitTimingEvent: emitTimingEvent,
          transportMetrics: transportMetrics,
          storeInInboxDetailed: storeInInboxDetailed,
          storeInAckCustodyInboxDetailed: storeInAckCustodyInboxDetailed,
          storeInMediaExpiryBoundedInboxDetailed:
              storeInMediaExpiryBoundedInboxDetailed,
          onDirectTextCustodyStaged: onDirectTextCustodyStaged,
          directEventFanout: directEventFanout,
          directLinkedMediaFanout: directLinkedMediaFanout,
          directPrivateMediaFanout: directPrivateMediaFanout,
          diagnosticTraceId: traceId,
        );
        final reason = switch (result.$1) {
          SendChatMessageResult.success => 'none',
          SendChatMessageResult.nodeNotRunning => 'offline',
          SendChatMessageResult.invalidMessage => 'invalid_payload',
          SendChatMessageResult.invalidPrivateMedia => 'unsupported',
          SendChatMessageResult.encryptionRequired => 'recipient_key_missing',
          SendChatMessageResult.mediaEncryptionRequired => 'metadata_invalid',
          SendChatMessageResult.peerNotFound => 'authority_rejected',
          SendChatMessageResult.dialFailed ||
          SendChatMessageResult.sendFailed => 'send_failed',
        };
        diagnostics.finishAttempt(
          feature: 'message',
          traceId: traceId,
          outcome: result.$1 == SendChatMessageResult.success
              ? result.$2?.status == 'delivered'
                    ? 'success'
                    : 'pending'
              : 'failed',
          reason: reason,
          values: {
            'durationMs': diagnosticTimer.elapsedMilliseconds,
            'direction': 'outgoing',
            'committed': result.$2 != null,
            'acknowledged': result.$2?.status == 'delivered',
          },
        );
        return result;
      } catch (_) {
        diagnostics.finishAttempt(
          feature: 'message',
          traceId: traceId,
          outcome: 'failed',
          reason: 'unknown',
          values: {
            'direction': 'outgoing',
            'durationMs': diagnosticTimer.elapsedMilliseconds,
          },
        );
        rethrow;
      }
    },
  );
}

Future<(SendChatMessageResult, ConversationMessage?)>
_sendChatMessageDiagnosed({
  required P2PService p2pService,
  required MessageRepository messageRepo,
  required String targetPeerId,
  required String text,
  required String senderPeerId,
  required String senderUsername,
  String action = MessagePayload.actionSend,
  String? editedAt,
  String? messageId,
  bool preassignedMessageIdIsFresh = false,
  String? timestamp,
  // F8 tier-2: a normal send stamps `dedupKey = its own id` (the default
  // below); one explicit Forward action passes its random operation token so
  // retry/redelivery dedups without coupling later actions to the source.
  String? dedupKey,
  bool isForwarded = false,
  String? createdAt,
  Bridge? bridge,
  String? recipientMlKemPublicKey,
  String? quotedMessageId,
  List<MediaAttachment>? mediaAttachments,
  PrivateMediaPolicy? privateMediaPolicy,
  MediaAttachmentRepository? mediaAttachmentRepo,
  bool emitTimingEvent = true,
  TransportMetrics? transportMetrics,
  StoreInInboxDetailedFn? storeInInboxDetailed,
  StoreInAckCustodyInboxDetailedFn? storeInAckCustodyInboxDetailed,
  StoreInMediaExpiryBoundedInboxDetailedFn?
  storeInMediaExpiryBoundedInboxDetailed,
  void Function(String messageId)? onDirectTextCustodyStaged,
  DirectEventFanoutAuthoring? directEventFanout,
  DirectLinkedMediaFanoutContext? directLinkedMediaFanout,
  DirectPrivateMediaFanoutContext? directPrivateMediaFanout,
  String? diagnosticTraceId,
}) async {
  final sendStopwatch = clock.stopwatch()..start();
  final liveDeadline = OutgoingLiveDeadline(() => sendStopwatch.elapsed);
  final targetPrefix = targetPeerId.length > 10
      ? targetPeerId.substring(0, 10)
      : targetPeerId;
  final sanitizedText = sanitizeMessageText(text);
  final hasAttachments =
      mediaAttachments != null && mediaAttachments.isNotEmpty;
  final hasAnyStrictBlobCommitment =
      hasAttachments &&
      mediaAttachments.any((attachment) => attachment.blobCustody != null);
  final hasCompleteStrictBlobManifest =
      hasAttachments &&
      mediaAttachments.every((attachment) {
        final commitment = attachment.blobCustody;
        return commitment != null &&
            commitment.isValid &&
            commitment.contentHash == attachment.contentHash;
      });
  final detailedInboxStore = p2pService is DetailedInboxStore
      ? p2pService as DetailedInboxStore
      : null;
  final effectiveStoreInInboxDetailed =
      storeInInboxDetailed ?? detailedInboxStore?.storeInInboxDetailed;
  final ackCustodyInboxStore = p2pService is AckOrExpiryInboxStore
      ? p2pService as AckOrExpiryInboxStore
      : null;
  final effectiveStoreInAckCustodyInboxDetailed =
      storeInAckCustodyInboxDetailed ??
      ackCustodyInboxStore?.storeInAckCustodyInboxDetailed;
  final mediaExpiryBoundedInboxStore =
      p2pService is MediaExpiryBoundedInboxStore
      ? p2pService as MediaExpiryBoundedInboxStore
      : null;
  final effectiveStoreInMediaExpiryBoundedInboxDetailed =
      storeInMediaExpiryBoundedInboxDetailed ??
      mediaExpiryBoundedInboxStore?.storeInMediaExpiryBoundedInboxDetailed;
  var connectionReused = false;
  var sendPath = 'unknown';
  Map<String, int> stepTimings = {};
  void emitSendTiming({
    required String outcome,
    Map<String, dynamic> details = const {},
  }) {
    AppDiagnostics.instance.record(
      feature: 'message',
      stage: outcome == 'success'
          ? 'send'
          : outcome.contains('encrypt')
          ? 'encrypt'
          : 'preflight',
      outcome: outcome == 'success'
          ? 'ok'
          : outcome.contains('retained')
          ? 'pending'
          : 'failed',
      reason: outcome == 'success'
          ? 'none'
          : outcome.contains('encrypt')
          ? 'encryption_failed'
          : outcome == 'invalid_private_media'
          ? 'unsupported'
          : outcome == 'invalid_message'
          ? 'invalid_payload'
          : outcome == 'node_not_running'
          ? 'offline'
          : outcome.contains('refused') || outcome.contains('blocked')
          ? 'authority_rejected'
          : 'send_failed',
      traceId: diagnosticTraceId,
      values: {
        'durationMs': sendStopwatch.elapsedMilliseconds,
        'direction': 'outgoing',
      },
    );
    if (!emitTimingEvent) return;
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_TIMING',
      details: {
        'elapsedMs': sendStopwatch.elapsedMilliseconds,
        'outcome': outcome,
        'hasAttachments': hasAttachments,
        'connectionReused': connectionReused,
        'sendPath': sendPath,
        ...stepTimings,
        ...details,
      },
    );
  }

  // NET-REL-04: record aggregate-only transport diagnostics at each terminal
  // send exit. Called exactly once per invocation (one rung per send).
  void recordMetrics({required String? transport, required String rung}) {
    transportMetrics?.recordRung(rung);
    transportMetrics?.recordSendLatency(
      transport: transport,
      latencyMs: sendStopwatch.elapsedMilliseconds,
    );
    if (transport != null) transportMetrics?.recordTransport(transport);
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'CHAT_MSG_SEND_START',
    details: {'targetPeerId': targetPrefix},
  );

  final directTextCustodyCapability =
      messageRepo is OutgoingDirectTextInboxCustodyRepository
      ? messageRepo as OutgoingDirectTextInboxCustodyRepository
      : null;
  final directTextCustodyRepo =
      directTextCustodyCapability?.supportsDirectTextInboxCustody == true
      ? directTextCustodyCapability
      : null;
  final directMutationCustodyCapability =
      messageRepo is OutgoingDirectTextMutationInboxCustodyRepository
      ? messageRepo as OutgoingDirectTextMutationInboxCustodyRepository
      : null;
  final directMutationCustodyRepo =
      directMutationCustodyCapability?.supportsDirectTextMutationInboxCustody ==
          true
      ? directMutationCustodyCapability
      : null;

  Future<(SendChatMessageResult, ConversationMessage?)> drainExistingCustody(
    DirectInboxCustodyOutboxEntry custody, {
    required String reason,
  }) async {
    final strictStore = effectiveStoreInAckCustodyInboxDetailed;
    if (strictStore == null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_SEND_CUSTODY_OWNER_RETAINED',
        details: {'id': shortenMessageId(custody.messageId), 'reason': reason},
      );
      emitSendTiming(outcome: 'custody_owner_retained');
      return (SendChatMessageResult.sendFailed, null);
    }
    final attempt = await drainOwnedDirectInboxCustodyOutboxEntry(
      entry: custody,
      custodyRepository: directTextCustodyRepo!,
      storeInAckCustodyInboxDetailed: strictStore,
      storeInMediaExpiryBoundedInboxDetailed:
          effectiveStoreInMediaExpiryBoundedInboxDetailed,
    );
    if (!attempt.completed) {
      emitSendTiming(outcome: 'custody_owner_retained');
      return (SendChatMessageResult.sendFailed, null);
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_CUSTODY_OWNER_COMPLETED',
      details: {'id': shortenMessageId(custody.messageId), 'reason': reason},
    );
    recordMetrics(transport: 'inbox', rung: 'inbox');
    emitSendTiming(outcome: 'success');
    return (SendChatMessageResult.success, null);
  }

  // 361: fresh blob-free text may be owned by the v113 fanout coordinator.
  // EDIT routing is deliberately deferred until after the persisted caption
  // classifier below: caller-supplied attachments (including an empty/stale
  // snapshot) are not authority for whether the durable parent is media.
  final fanoutEligibleShape =
      directEventFanout != null &&
      !hasAttachments &&
      action == MessagePayload.actionSend &&
      (privateMediaPolicy == null ||
          privateMediaPolicy.mode == PrivateMediaMode.ordinary);

  // Survivor-first: for a retried fresh send, ANY surviving fanout sibling is
  // the complete pending set. It is discovered BEFORE the roster resolver and
  // BEFORE any bridge crypto, and is drained through the incumbent per-row
  // owner without consulting the current roster.
  if (fanoutEligibleShape &&
      action == MessagePayload.actionSend &&
      messageId != null) {
    final siblingRows = await directEventFanout.loadTextSiblings(messageId);
    final fanoutSurvivors = siblingRows
        .where((row) => row['contact_account_peer_id'] != null)
        .toList(growable: false);
    if (fanoutSurvivors.isNotEmpty) {
      final strictStore = effectiveStoreInAckCustodyInboxDetailed;
      if (strictStore == null || directTextCustodyRepo == null) {
        emitSendTiming(outcome: 'fanout_survivors_retained');
        return (SendChatMessageResult.sendFailed, null);
      }
      var allCompleted = true;
      for (final row in fanoutSurvivors) {
        final attempt = await drainOwnedDirectInboxCustodyOutboxEntry(
          entry: DirectInboxCustodyOutboxEntry.fromMap(row),
          custodyRepository: directTextCustodyRepo,
          storeInAckCustodyInboxDetailed: strictStore,
          storeInMediaExpiryBoundedInboxDetailed:
              effectiveStoreInMediaExpiryBoundedInboxDetailed,
        );
        allCompleted = allCompleted && attempt.completed;
      }
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_SEND_FANOUT_SURVIVORS_DRAINED',
        details: {
          'id': shortenMessageId(messageId),
          'survivors': fanoutSurvivors.length,
          'completed': allCompleted,
        },
      );
      if (!allCompleted) {
        emitSendTiming(outcome: 'fanout_survivors_retained');
        return (SendChatMessageResult.sendFailed, null);
      }
      recordMetrics(transport: 'inbox', rung: 'inbox');
      emitSendTiming(outcome: 'success');
      return (
        SendChatMessageResult.success,
        await messageRepo.getMessage(messageId),
      );
    }
  }

  DirectEventFanoutRouting? fanoutRouting;
  if (fanoutEligibleShape) {
    final routing = await directEventFanout.decideRoute(targetPeerId);
    switch (routing.route) {
      case DirectEventFanoutRoute.incumbentLegacy:
        fanoutRouting = null;
      case DirectEventFanoutRoute.refusedSelectorOff:
      case DirectEventFanoutRoute.refusedUnavailable:
        // Refusal happens BEFORE target crypto/network and never demotes to
        // the incumbent single legacy target.
        emitSendTiming(outcome: 'fanout_refused_${routing.route.name}');
        return (SendChatMessageResult.sendFailed, null);
      case DirectEventFanoutRoute.fanout:
        fanoutRouting = routing;
    }
  }

  DirectInboxCustodyOutboxEntry? preexistingDirectMediaCustody;
  if (fanoutRouting == null &&
      action == MessagePayload.actionSend &&
      messageId != null &&
      directTextCustodyRepo != null) {
    try {
      final custody = await directTextCustodyRepo
          .loadDirectInboxCustodyOwnerForMessageId(messageId: messageId);
      if (custody != null &&
          !_isExactDirectInboxCustodyReplay(
            custody: custody,
            messageId: messageId,
            senderPeerId: senderPeerId,
          )) {
        emitFlowEvent(
          layer: 'FL',
          event: 'CHAT_MSG_SEND_MEDIA_CUSTODY_REPLAY_REFUSED',
          details: {'id': shortenMessageId(messageId)},
        );
        emitSendTiming(outcome: 'media_custody_replay_refused');
        return (SendChatMessageResult.sendFailed, null);
      }
      if (custody != null && custody.recipientPeerId != targetPeerId) {
        return drainExistingCustody(custody, reason: 'caller_recipient_drift');
      }
      preexistingDirectMediaCustody = custody;
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_SEND_MEDIA_CUSTODY_REPLAY_ERROR',
        details: {
          'id': shortenMessageId(messageId),
          'errorType': error.runtimeType.toString(),
        },
      );
      emitSendTiming(outcome: 'media_custody_replay_error');
      return (SendChatMessageResult.sendFailed, null);
    }
  }

  ConversationMessage? existingOutgoing;
  try {
    existingOutgoing = messageId == null
        ? null
        : await messageRepo.getMessage(messageId);
  } catch (error) {
    final custody = preexistingDirectMediaCustody;
    if (custody != null) {
      return drainExistingCustody(custody, reason: 'parent_read_error');
    }
    // No immutable owner can absorb the failure. Convert the escaping
    // repository exception into a definitive non-staged result.
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_PRE_STAGE_READ_ERROR',
      details: {'errorType': error.runtimeType.toString()},
    );
    emitSendTiming(outcome: 'pre_stage_read_error');
    return (SendChatMessageResult.sendFailed, null);
  }
  final custody = preexistingDirectMediaCustody;
  if (custody != null &&
      existingOutgoing != null &&
      existingOutgoing.contactPeerId != custody.recipientPeerId) {
    return drainExistingCustody(custody, reason: 'parent_recipient_drift');
  }

  // A globally-owned v108 row is type-opaque immutable authority. Caller
  // shape (including omitted media or empty text) cannot strand or reinterpret
  // those bytes. Without an owner, preserve the ordinary input validation.
  if (preexistingDirectMediaCustody == null &&
      sanitizedText.trim().isEmpty &&
      !hasAttachments) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_INVALID',
      details: {'reason': 'empty_text'},
    );
    emitSendTiming(outcome: 'invalid_message');
    return (SendChatMessageResult.invalidMessage, null);
  }
  final effectivePrivateMediaPolicy = preexistingDirectMediaCustody != null
      ? const PrivateMediaPolicy.ordinary()
      : privateMediaPolicy ??
            (existingOutgoing != null && !existingOutgoing.isIncoming
                ? existingOutgoing.privateMediaPolicy
                : const PrivateMediaPolicy.ordinary());

  // 359 (D-234-01): private caption/text EDIT is an unsupported product
  // action, so the DURABLE target — not the caller's snapshot — decides. A
  // forged ordinary policy or stale media list would otherwise reinterpret a
  // persisted redacted parent as an ordinary edit. This runs before the
  // recipient crypto/envelope construction, any staging seam and any network
  // work; the recipient key is already an argument here, so no separately
  // observable key lookup is claimed.
  if (action == MessagePayload.actionEdit &&
      existingOutgoing != null &&
      !existingOutgoing.isIncoming &&
      existingOutgoing.privateMediaPolicy.requiresRedaction) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_INVALID_PRIVATE_MEDIA',
      details: const {'reason': 'private_target_edit_unsupported'},
    );
    emitSendTiming(outcome: 'invalid_private_media');
    return (SendChatMessageResult.invalidPrivateMedia, null);
  }

  // 358: the exact newly authored v1 disappearing image/video initial is the
  // ONLY non-ordinary shape a v110 token may carry. Everything else about the
  // token's exclusivity is unchanged.
  final isExactDisappearingTokenBearingInitial =
      action == MessagePayload.actionSend &&
      hasAttachments &&
      mediaAttachments.length == 1 &&
      sanitizedText.isEmpty &&
      quotedMessageId == null &&
      !isForwarded &&
      disappearingMediaInitialProducerMatrixAllows(
        policyVersion: effectivePrivateMediaPolicy.version,
        mode: effectivePrivateMediaPolicy.mode,
        durationSeconds: effectivePrivateMediaPolicy.durationSeconds,
        mime: mediaAttachments.single.mime,
        mediaType: mediaAttachments.single.mediaType,
      );

  // A v110 intent is exclusive preparation authority. It may only enter the
  // exact ordinary (or, since 358, exact disappearing) initial-media
  // acquisition path; an empty-media call, edit, delete, or private-policy
  // reinterpretation must not fall through to a weaker generic/private staging
  // seam after doing envelope work.
  if (preexistingDirectMediaCustody == null &&
      existingOutgoing?.directMediaCustodyIntentId != null &&
      !isExactDisappearingTokenBearingInitial &&
      (action != MessagePayload.actionSend ||
          !hasAttachments ||
          effectivePrivateMediaPolicy.version != 0 ||
          effectivePrivateMediaPolicy.mode != PrivateMediaMode.ordinary)) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_MEDIA_CUSTODY_EXCLUSIVE_PATH_REFUSED',
      details: {'id': shortenMessageId(messageId!)},
    );
    emitSendTiming(outcome: 'media_custody_exclusive_path_refused');
    return (SendChatMessageResult.sendFailed, null);
  }
  if (effectivePrivateMediaPolicy.mode != PrivateMediaMode.ordinary) {
    final eligibility = _privateMediaEligibilityForSend(
      text: sanitizedText,
      action: action,
      isForwarded: isForwarded,
      attachments: mediaAttachments,
    );
    final validated = effectivePrivateMediaPolicy.validatedFor(eligibility);
    if (effectivePrivateMediaPolicy.isUnsupported ||
        !effectivePrivateMediaPolicy.isPrivate ||
        validated.isUnsupported) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_SEND_INVALID_PRIVATE_MEDIA',
        details: const {'reason': 'ineligible_shape'},
      );
      emitSendTiming(outcome: 'invalid_private_media');
      return (SendChatMessageResult.invalidPrivateMedia, null);
    }
  }

  if (action == MessagePayload.actionEdit &&
      (messageId == null || timestamp == null || createdAt == null)) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_INVALID',
      details: {'reason': 'edit_requires_existing_message_contract'},
    );
    emitSendTiming(outcome: 'invalid_message');
    return (SendChatMessageResult.invalidMessage, null);
  }

  // 116 EF-2 no-downgrade writer gate: a plain send under a message id whose
  // outgoing row carries editedAt or deletedAt would transmit downgraded
  // content AND poison the stored edit/deletion envelope via pre-race attempt
  // staging below. Fail closed BEFORE encryption and before any
  // persist. All UI retry paths route through retryFailedMessage, so this
  // gate has zero legitimate trips — any field occurrence is a bug detector.
  if (preexistingDirectMediaCustody == null &&
      action == MessagePayload.actionSend &&
      messageId != null) {
    final existing = existingOutgoing;
    if (existing != null &&
        !existing.isIncoming &&
        (existing.editedAt != null || existing.isDeleted)) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_SEND_ACTION_DOWNGRADE_BLOCKED',
        details: {
          'id': messageId.length > 8 ? messageId.substring(0, 8) : messageId,
          'reason': existing.isDeleted
              ? 'deleted_row_plain_send'
              : 'edited_row_plain_send',
        },
      );
      emitSendTiming(outcome: 'action_downgrade_blocked');
      return (SendChatMessageResult.invalidMessage, null);
    }
  }

  final isOutgoingPrivateOneMoreLook =
      effectivePrivateMediaPolicy.version == 1 &&
      (effectivePrivateMediaPolicy.mode == PrivateMediaMode.protected ||
          effectivePrivateMediaPolicy.mode == PrivateMediaMode.viewOnce);
  final attemptKind = action == MessagePayload.actionEdit
      ? OutgoingOrdinaryAttemptKind.edit
      : existingOutgoing?.directMediaCustodyIntentId != null
      ? OutgoingOrdinaryAttemptKind.existing
      : messageId == null || preassignedMessageIdIsFresh
      ? OutgoingOrdinaryAttemptKind.fresh
      : OutgoingOrdinaryAttemptKind.existing;
  final ownsDirectTextInboxCustody =
      !isOutgoingPrivateOneMoreLook &&
      attemptKind == OutgoingOrdinaryAttemptKind.fresh &&
      action == MessagePayload.actionSend &&
      !hasAttachments &&
      effectivePrivateMediaPolicy.mode == PrivateMediaMode.ordinary;
  final isDirectTextMutationInboxCustodyCandidate =
      !isOutgoingPrivateOneMoreLook &&
      attemptKind == OutgoingOrdinaryAttemptKind.edit &&
      action == MessagePayload.actionEdit &&
      !hasAttachments &&
      effectivePrivateMediaPolicy.version == 0 &&
      effectivePrivateMediaPolicy.mode == PrivateMediaMode.ordinary &&
      existingOutgoing != null &&
      !existingOutgoing.isIncoming &&
      !existingOutgoing.isDeleted &&
      existingOutgoing.contactPeerId == targetPeerId &&
      existingOutgoing.senderPeerId == senderPeerId &&
      existingOutgoing.directMediaCustodyIntentId == null;
  // 358: exactly one newly authored v1 disappearing image/video initial adopts
  // the same token-bearing ordinary owners. It is admitted ONLY from a durable
  // v110 predecessor (`existing` + intent), never from the marker-free fresh
  // arm, so external share and internal forward stay ordinary-only.
  final isTokenBearingDisappearingMedia =
      isExactDisappearingTokenBearingInitial &&
      attemptKind == OutgoingOrdinaryAttemptKind.existing &&
      existingOutgoing?.directMediaCustodyIntentId != null;
  var ownsDirectMediaInboxCustody =
      !isOutgoingPrivateOneMoreLook &&
      action == MessagePayload.actionSend &&
      hasAttachments &&
      (effectivePrivateMediaPolicy.mode == PrivateMediaMode.ordinary
          ? ((attemptKind == OutgoingOrdinaryAttemptKind.fresh &&
                    existingOutgoing == null) ||
                (attemptKind == OutgoingOrdinaryAttemptKind.existing &&
                    existingOutgoing?.directMediaCustodyIntentId != null))
          : isTokenBearingDisappearingMedia);
  final ordinaryMutationRepo =
      messageRepo is OutgoingTransportMutationRepository
      ? messageRepo as OutgoingTransportMutationRepository
      : null;
  final directMediaCustodyCapability =
      mediaAttachmentRepo is OutgoingDirectMediaInboxCustodyStagingRepository
      ? mediaAttachmentRepo as OutgoingDirectMediaInboxCustodyStagingRepository
      : null;
  final directMediaCustodyRepo =
      directMediaCustodyCapability?.supportsDirectMediaInboxCustody == true
      ? directMediaCustodyCapability
      : null;
  final directLinkedMediaFanoutCapability =
      mediaAttachmentRepo is OutgoingDirectLinkedMediaBlobFanoutRepository
      ? mediaAttachmentRepo as OutgoingDirectLinkedMediaBlobFanoutRepository
      : null;
  final ownsDirectLinkedMediaFanout =
      directLinkedMediaFanout != null &&
      directLinkedMediaFanoutCapability?.supportsDirectLinkedMediaBlobFanout ==
          true;
  final directPrivateMediaFanoutCapability =
      messageRepo is OutgoingDirectPrivateMediaFanoutInboxCustodyRepository
      ? messageRepo as OutgoingDirectPrivateMediaFanoutInboxCustodyRepository
      : null;
  final ownsDirectPrivateMediaFanout =
      directPrivateMediaFanout != null &&
      directPrivateMediaFanoutCapability
              ?.supportsOutgoingDirectPrivateMediaFanoutInboxCustody ==
          true;

  // 353: persisted media authority is consulted BEFORE any caller-derived
  // attachment gate. A caption-only EDIT of a proven strict generation takes
  // exact v109 custody and ignores the caller's media list entirely; the
  // caller may not add, remove, reorder or re-key a published attachment.
  final captionEditCapability =
      mediaAttachmentRepo
          is OutgoingDirectMediaCaptionEditInboxCustodyRepository
      ? mediaAttachmentRepo
            as OutgoingDirectMediaCaptionEditInboxCustodyRepository
      : null;
  final directMediaCaptionEditRepo =
      captionEditCapability?.supportsDirectMediaCaptionEditInboxCustody == true
      ? captionEditCapability
      : null;
  final isOrdinaryDirectEditCandidate =
      !isOutgoingPrivateOneMoreLook &&
      action == MessagePayload.actionEdit &&
      attemptKind == OutgoingOrdinaryAttemptKind.edit &&
      preexistingDirectMediaCustody == null &&
      messageId != null &&
      effectivePrivateMediaPolicy.version == 0 &&
      effectivePrivateMediaPolicy.mode == PrivateMediaMode.ordinary &&
      existingOutgoing != null &&
      !existingOutgoing.isIncoming &&
      !existingOutgoing.isDeleted &&
      existingOutgoing.directMediaCustodyIntentId == null;
  // A media candidate is anything the caller or the loaded parent projects as
  // carrying attachments. Only the repository capability is authority, so an
  // absent capability over a candidate fails closed rather than guessing.
  final looksLikeMediaEditCandidate =
      isOrdinaryDirectEditCandidate &&
      (hasAttachments || existingOutgoing.media.isNotEmpty);
  OutgoingDirectMediaCaptionEditAuthority? captionEditAuthority;
  if (isOrdinaryDirectEditCandidate && directMediaCaptionEditRepo != null) {
    try {
      captionEditAuthority = await directMediaCaptionEditRepo
          .qualifyOutgoingDirectMediaCaptionEdit(messageId);
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_SEND_MEDIA_CAPTION_EDIT_QUALIFY_ERROR',
        details: {
          'id': shortenMessageId(messageId),
          'errorType': error.runtimeType.toString(),
        },
      );
      captionEditAuthority =
          const OutgoingDirectMediaCaptionEditAuthority.contradiction();
    }
  }
  final canonicalCaptionParent = captionEditAuthority?.parent;
  final captionEditIdentityMatches =
      canonicalCaptionParent != null &&
      canonicalCaptionParent.id == messageId &&
      canonicalCaptionParent.contactPeerId == targetPeerId &&
      canonicalCaptionParent.senderPeerId == senderPeerId;
  final captionEditRefused =
      captionEditAuthority?.lane ==
          OutgoingDirectMediaCaptionEditLane.contradiction ||
      (captionEditAuthority?.lane ==
              OutgoingDirectMediaCaptionEditLane.strictMedia &&
          (!captionEditIdentityMatches ||
              captionEditAuthority!.attachments.isEmpty)) ||
      (looksLikeMediaEditCandidate && directMediaCaptionEditRepo == null);
  if (captionEditRefused) {
    // The supplied recipient key cannot be safely retargeted and a crossed
    // generation must never be republished. Refuse before key lookup,
    // encryption, persistence or network.
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_MEDIA_CAPTION_EDIT_REFUSED',
      details: {
        'id': shortenMessageId(messageId!),
        'reason': directMediaCaptionEditRepo == null
            ? 'missing_media_caption_edit_capability'
            : captionEditAuthority?.lane ==
                  OutgoingDirectMediaCaptionEditLane.contradiction
            ? 'contradiction'
            : 'identity_drift',
      },
    );
    emitSendTiming(outcome: 'media_caption_edit_refused');
    return (SendChatMessageResult.sendFailed, null);
  }
  final ownsDirectMediaCaptionEditInboxCustody =
      captionEditAuthority?.lane ==
      OutgoingDirectMediaCaptionEditLane.strictMedia;
  if (ownsDirectMediaCaptionEditInboxCustody) {
    // Canonical persisted identity replaces every non-identity caller field.
    existingOutgoing = canonicalCaptionParent;
  }
  final canonicalCaptionAttachments = ownsDirectMediaCaptionEditInboxCustody
      ? captionEditAuthority!.attachments
      : null;
  final effectiveMediaAttachments =
      canonicalCaptionAttachments ?? mediaAttachments;
  // A caption EDIT publishes NO blob commitment: the immutable generation is
  // already proven by v108/v111 and the persisted per-attachment lineage.
  final effectiveHasAnyStrictBlobCommitment =
      !ownsDirectMediaCaptionEditInboxCustody && hasAnyStrictBlobCommitment;
  final effectiveHasCompleteStrictBlobManifest =
      !ownsDirectMediaCaptionEditInboxCustody && hasCompleteStrictBlobManifest;

  // A persisted media classification always defeats the caller's attachment
  // shape. Only a proven non-media (or a legacy repository without the media
  // classifier and no media-looking parent) may retain the text-mutation lane.
  final ownsDirectTextMutationInboxCustody =
      isDirectTextMutationInboxCustodyCandidate &&
      (captionEditAuthority == null ||
          captionEditAuthority.lane ==
              OutgoingDirectMediaCaptionEditLane.notMedia);

  // 366: resolve EDIT fanout only after durable qualification. Both ordinary
  // text EDIT and a strict ordinary media-caption EDIT are blob-free mutation
  // events, but the latter must carry the canonical persisted media descriptor
  // in every independently encrypted inner payload.
  if (directEventFanout != null &&
      action == MessagePayload.actionEdit &&
      (ownsDirectTextMutationInboxCustody ||
          ownsDirectMediaCaptionEditInboxCustody)) {
    final routing = await directEventFanout.decideRoute(targetPeerId);
    switch (routing.route) {
      case DirectEventFanoutRoute.incumbentLegacy:
        fanoutRouting = null;
      case DirectEventFanoutRoute.refusedSelectorOff:
      case DirectEventFanoutRoute.refusedUnavailable:
        emitSendTiming(outcome: 'fanout_refused_${routing.route.name}');
        return (SendChatMessageResult.sendFailed, null);
      case DirectEventFanoutRoute.fanout:
        fanoutRouting = routing;
    }
  }

  // 354: exactly one newly authored v1 Protected image/video or View-Once
  // image initial carrying a complete strict blob manifest adopts the same
  // exact ACK-or-expiry v108 ownership. Every other private shape (edit,
  // delete, disappearing, proof-less legacy, selector-off) is unchanged.
  final privateInboxCustodyCapability =
      messageRepo is OutgoingDirectPrivateMediaInboxCustodyRepository
      ? messageRepo as OutgoingDirectPrivateMediaInboxCustodyRepository
      : null;
  final ownsDirectPrivateMediaInboxCustody =
      isOutgoingPrivateOneMoreLook &&
      action == MessagePayload.actionSend &&
      hasAttachments &&
      effectiveHasCompleteStrictBlobManifest &&
      (effectiveMediaAttachments?.length ?? 0) == 1 &&
      privateMediaInitialProducerMatrixAllows(
        policyVersion: effectivePrivateMediaPolicy.version,
        mode: effectivePrivateMediaPolicy.mode,
        mime: effectiveMediaAttachments!.single.mime,
        mediaType: effectiveMediaAttachments.single.mediaType,
      ) &&
      (ownsDirectPrivateMediaFanout ||
          privateInboxCustodyCapability
                  ?.supportsOutgoingDirectPrivateMediaInboxCustody ==
              true);
  var ownsDirectInboxCustody =
      ownsDirectTextInboxCustody ||
      ownsDirectTextMutationInboxCustody ||
      ownsDirectMediaCaptionEditInboxCustody ||
      ownsDirectMediaInboxCustody ||
      ownsDirectPrivateMediaInboxCustody;
  // Every v109-owned mutation shares one lifecycle: text and media caption
  // events retain byte-identical obligations and converge through the same
  // drain, completion and failure paths.
  final ownsDirectMutationInboxCustody =
      ownsDirectTextMutationInboxCustody ||
      ownsDirectMediaCaptionEditInboxCustody;
  final directMutationLifecycleCapability =
      messageRepo is DirectMutationInboxCustodyLifecycleRepository
      ? messageRepo as DirectMutationInboxCustodyLifecycleRepository
      : null;
  final directMutationLifecycleRepo =
      directMutationLifecycleCapability
              ?.supportsDirectMutationInboxCustodyLifecycle ==
          true
      ? directMutationLifecycleCapability
      : null;

  // 112 G5: reject malformed or non-direct media before consulting optional
  // custody capabilities. This remains the earliest media-specific boundary,
  // so invalid blob metadata cannot be masked as a repository-composition
  // failure and no envelope/encryption work can begin.
  final mediaGateReason = preexistingDirectMediaCustody == null
      ? effectiveHasAnyStrictBlobCommitment &&
                !effectiveHasCompleteStrictBlobManifest
            ? 'partial_blob_custody_manifest'
            : _sanitizeDirectMediaAttachments(effectiveMediaAttachments)
      : null;
  if (mediaGateReason != null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'DIRECT_MEDIA_ENCRYPTION_REQUIRED',
      details: {'reason': mediaGateReason},
    );
    emitSendTiming(
      outcome: 'media_encryption_required',
      details: {'reason': mediaGateReason},
    );
    return (SendChatMessageResult.mediaEncryptionRequired, null);
  }

  final replayedDirectMediaCustody = preexistingDirectMediaCustody;
  final replayedDirectMediaMessage =
      replayedDirectMediaCustody != null &&
          existingOutgoing != null &&
          !existingOutgoing.isIncoming &&
          existingOutgoing.id == messageId &&
          existingOutgoing.contactPeerId == targetPeerId &&
          existingOutgoing.senderPeerId == senderPeerId
      ? existingOutgoing
      : null;
  if (replayedDirectMediaCustody != null) {
    ownsDirectMediaInboxCustody = true;
    ownsDirectInboxCustody = true;
  }

  // A strict-looking wire commitment is authorized only by a fresh Plan 347
  // acquisition, an exact prepared intent, or an immutable v108 replay. An
  // existing/pre-v111 row without that authority must never fall through to
  // the legacy media staging transaction, which cannot bind or validate v111.
  if (effectiveHasAnyStrictBlobCommitment &&
      !ownsDirectMediaInboxCustody &&
      !ownsDirectPrivateMediaInboxCustody) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_MEDIA_CUSTODY_PREFLIGHT_REFUSED',
      details: const {'reason': 'strict_manifest_without_owned_custody'},
    );
    emitSendTiming(outcome: 'media_custody_preflight_refused');
    return (SendChatMessageResult.sendFailed, null);
  }

  final missingStrictMediaCustodyStore =
      !ownsDirectLinkedMediaFanout &&
      !ownsDirectPrivateMediaFanout &&
      (ownsDirectMediaInboxCustody || ownsDirectPrivateMediaInboxCustody) &&
      (effectiveStoreInAckCustodyInboxDetailed == null ||
          (effectiveHasCompleteStrictBlobManifest &&
              effectiveStoreInMediaExpiryBoundedInboxDetailed == null));

  if (ownsDirectInboxCustody &&
      ((ordinaryMutationRepo == null && !ownsDirectPrivateMediaInboxCustody) ||
          (ownsDirectPrivateMediaInboxCustody &&
              directTextCustodyRepo == null) ||
          (ownsDirectTextInboxCustody && directTextCustodyRepo == null) ||
          (ownsDirectTextMutationInboxCustody &&
              directMutationCustodyRepo == null) ||
          (ownsDirectMutationInboxCustody &&
              directMutationLifecycleRepo == null) ||
          (ownsDirectMediaInboxCustody &&
              replayedDirectMediaCustody == null &&
              directMediaCustodyRepo == null &&
              !ownsDirectLinkedMediaFanout) ||
          missingStrictMediaCustodyStore)) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_ATTEMPT_STAGE_REFUSED',
      details: {
        'reason':
            ordinaryMutationRepo == null && !ownsDirectPrivateMediaInboxCustody
            ? 'missing_message_capability'
            : (ownsDirectTextInboxCustody ||
                      ownsDirectPrivateMediaInboxCustody) &&
                  directTextCustodyRepo == null
            ? 'missing_direct_inbox_custody_capability'
            : ownsDirectTextMutationInboxCustody &&
                  directMutationCustodyRepo == null
            ? 'missing_direct_mutation_custody_capability'
            : ownsDirectMutationInboxCustody &&
                  directMutationLifecycleRepo == null
            ? 'missing_direct_mutation_lifecycle_capability'
            : missingStrictMediaCustodyStore
            ? 'missing_ack_or_expiry_store_capability'
            : 'missing_direct_media_custody_capability',
      },
    );
    emitSendTiming(outcome: 'attempt_stage_refused');
    return (SendChatMessageResult.sendFailed, null);
  }
  final recipientKey = recipientMlKemPublicKey?.trim();
  final nodeWasNotRunningAtEntry = !p2pService.currentState.isStarted;
  final canStageCustodyBeforeNodeNotRunning =
      nodeWasNotRunningAtEntry &&
      ownsDirectInboxCustody &&
      (ordinaryMutationRepo != null || ownsDirectPrivateMediaInboxCustody) &&
      (!ownsDirectPrivateMediaInboxCustody || directTextCustodyRepo != null) &&
      (!ownsDirectTextInboxCustody || directTextCustodyRepo != null) &&
      (!ownsDirectTextMutationInboxCustody ||
          directMutationCustodyRepo != null) &&
      (!ownsDirectMutationInboxCustody ||
          directMutationLifecycleRepo != null) &&
      (!ownsDirectMediaInboxCustody ||
          replayedDirectMediaCustody != null ||
          directMediaCustodyRepo != null ||
          ownsDirectLinkedMediaFanout) &&
      (replayedDirectMediaCustody != null ||
          (bridge != null &&
              (directLinkedMediaFanout != null ||
                  directPrivateMediaFanout != null ||
                  (recipientKey != null && recipientKey.isNotEmpty))));

  // Preserve the historical pre-encryption return for paths that do not own
  // newly-authored direct-text custody, or cannot atomically acquire it. A
  // capable fresh text send continues through encryption/staging so a stopped
  // node cannot strand a UI-only optimistic bubble without durable custody.
  if (nodeWasNotRunningAtEntry && !canStageCustodyBeforeNodeNotRunning) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_NODE_NOT_RUNNING',
      details: {},
    );
    emitSendTiming(outcome: 'node_not_running');
    return (SendChatMessageResult.nodeNotRunning, null);
  }

  if (replayedDirectMediaCustody == null &&
      (bridge == null ||
          (directLinkedMediaFanout == null &&
              directPrivateMediaFanout == null &&
              (recipientKey == null || recipientKey.isEmpty)))) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_ENCRYPTION_REQUIRED',
      details: {
        'reason': bridge == null ? 'missing_bridge' : 'missing_recipient_key',
      },
    );
    emitSendTiming(
      outcome: 'encryption_required',
      details: {
        'reason': bridge == null ? 'missing_bridge' : 'missing_recipient_key',
      },
    );
    return (SendChatMessageResult.encryptionRequired, null);
  }

  // 3. Build payload
  final resolvedMessageId = messageId ?? _uuid.v4();
  if (diagnosticTraceId != null) {
    AppDiagnostics.instance.traceForOperation(
      'message:$resolvedMessageId',
      propagatedTraceId: diagnosticTraceId,
    );
    for (final attachment in mediaAttachments ?? const <MediaAttachment>[]) {
      AppDiagnostics.instance.traceForOperation(
        'media:${attachment.id}',
        propagatedTraceId: diagnosticTraceId,
      );
    }
  }
  final resolvedTimestamp = ownsDirectMediaCaptionEditInboxCustody
      ? existingOutgoing!.timestamp
      : timestamp ??
            replayedDirectMediaMessage?.timestamp ??
            existingOutgoing?.timestamp ??
            DateTime.now().toUtc().toIso8601String();
  // F8 tier-2: default a fresh normal send's dedupKey to its own id; one
  // Forward action keeps its operation token when a destination id/timestamp
  // is re-minted or retried. An existing legacy row may deliberately have a
  // NULL dedup key, which is part of the exact attempt snapshot and must not
  // be silently minted during retry staging.
  final resolvedDedupKey = ownsDirectMediaCaptionEditInboxCustody
      ? existingOutgoing!.dedupKey
      : dedupKey ??
            (messageId != null && existingOutgoing != null
                ? existingOutgoing.dedupKey
                : resolvedMessageId);
  // Non-identity caller drift is ignored: the persisted parent is the only
  // authority for a caption-only EDIT's stable payload columns.
  final effectiveQuotedMessageId = ownsDirectMediaCaptionEditInboxCustody
      ? existingOutgoing!.quotedMessageId
      : quotedMessageId;
  final effectiveIsForwarded = ownsDirectMediaCaptionEditInboxCustody
      ? existingOutgoing!.isForwarded
      : isForwarded;
  final resolvedEditedAt = action == MessagePayload.actionEdit
      ? _resolveStrictlyNewerEditedAt(
          priorEditedAt: existingOutgoing?.editedAt,
          requestedEditedAt: editedAt,
        )
      : null;
  if (action == MessagePayload.actionEdit && resolvedEditedAt == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_EDIT_ORDER_REFUSED',
      details: {'id': shortenMessageId(resolvedMessageId)},
    );
    emitSendTiming(outcome: 'edit_order_refused');
    return (SendChatMessageResult.sendFailed, null);
  }
  // Relay inbox dedupe keys encrypted chat events by cleartext outer identity.
  // An edit targets the original message id but is a different immutable wire
  // event, so it receives an authenticated event id of its own.
  final resolvedEventId = action == MessagePayload.actionEdit
      ? _uuid.v4()
      : null;

  // 361: the v113 all-target fanout branch. Everything above proved the
  // blob-free ordinary shape; anything the batch owner cannot own refuses
  // rather than demoting to the single legacy target.
  if (fanoutRouting != null) {
    final eligibleFanoutShape =
        !isOutgoingPrivateOneMoreLook &&
        effectivePrivateMediaPolicy.version == 0 &&
        effectivePrivateMediaPolicy.mode == PrivateMediaMode.ordinary &&
        (action == MessagePayload.actionSend
            ? attemptKind == OutgoingOrdinaryAttemptKind.fresh
            : attemptKind == OutgoingOrdinaryAttemptKind.edit &&
                  existingOutgoing != null &&
                  !existingOutgoing.isIncoming &&
                  !existingOutgoing.isDeleted &&
                  existingOutgoing.contactPeerId == targetPeerId &&
                  existingOutgoing.senderPeerId == senderPeerId &&
                  existingOutgoing.directMediaCustodyIntentId == null);
    if (!eligibleFanoutShape) {
      emitSendTiming(outcome: 'fanout_shape_refused');
      return (SendChatMessageResult.sendFailed, null);
    }
    return _authorDirectBlobFreeTextFanout(
      directEventFanout: directEventFanout!,
      routing: fanoutRouting,
      p2pService: p2pService,
      messageRepo: messageRepo,
      directTextCustodyRepo: directTextCustodyRepo,
      directMutationCustodyRepo: directMutationCustodyRepo,
      storeInAckCustodyInboxDetailed: effectiveStoreInAckCustodyInboxDetailed,
      storeInMediaExpiryBoundedInboxDetailed:
          effectiveStoreInMediaExpiryBoundedInboxDetailed,
      action: action,
      targetPeerId: targetPeerId,
      senderPeerId: senderPeerId,
      senderUsername: senderUsername,
      sanitizedText: sanitizedText,
      resolvedMessageId: resolvedMessageId,
      resolvedTimestamp: resolvedTimestamp,
      resolvedEventId: resolvedEventId,
      resolvedEditedAt: resolvedEditedAt,
      resolvedDedupKey: resolvedDedupKey,
      quotedMessageId: effectiveQuotedMessageId,
      isForwarded: effectiveIsForwarded,
      media: ownsDirectMediaCaptionEditInboxCustody
          ? canonicalCaptionAttachments!
                .map((attachment) => attachment.toJson())
                .toList(growable: false)
          : null,
      createdAt: createdAt,
      existingOutgoing: existingOutgoing,
      onDirectTextCustodyStaged: onDirectTextCustodyStaged,
      emitSendTiming: emitSendTiming,
      recordMetrics: recordMetrics,
    );
  }
  final normalizedAttachments = effectiveMediaAttachments
      ?.map(
        (attachment) => attachment.copyWith(
          messageId: resolvedMessageId,
          createdAt: attachment.createdAt.isEmpty
              ? resolvedTimestamp
              : attachment.createdAt,
          // This use case is the canonical 1:1 outbound boundary. Upload and
          // share producers intentionally cannot infer a local DB lane, but
          // every attachment leaving this boundary is direct-owned — matching
          // the typed repository write below and the row that rehydrates after
          // restart. Keep this local-only stamp out of the wire via toJson().
          ownerLane: MediaOwnerLane.direct,
        ),
      )
      .toList();
  final strictWireManifest = effectiveHasCompleteStrictBlobManifest
      ? normalizedAttachments!
            .map(
              (attachment) => DirectMediaBlobManifestProjection(
                attachmentId: attachment.id,
                commitment: attachment.blobCustody!,
              ),
            )
            .toList(growable: false)
      : null;
  final wireMediaBlobManifestHash = strictWireManifest == null
      ? null
      : computeDirectMediaBlobManifestHash(strictWireManifest);
  final wireMediaBlobExpiresAtMs = strictWireManifest == null
      ? null
      : earliestDirectMediaBlobExpiryMs(strictWireManifest);

  // A prepared media send is authorized by durable provenance, never by the
  // caller's flag or its in-memory attachment list. Reload the parent and the
  // complete direct-owned projection before encryption; the combined SQL
  // transaction repeats these checks after serialization to close the race.
  if (ownsDirectMediaInboxCustody && replayedDirectMediaCustody == null) {
    // 362 plural-authority-first: a marked linked generation may settle ONLY
    // through the plural fanout stage. The persisted survivors ARE the
    // authority, so a producer that uploaded through the all-target owner
    // needs no caller-threaded context: it is self-assembled here from the
    // stored rows. Anything underivable — missing capability, incoherent or
    // unstored rows — refuses
    // this singular path before encryption or network, and an unreadable
    // authority likewise fails closed.
    if (directLinkedMediaFanout == null &&
        mediaAttachmentRepo is DirectMediaBlobCustodyRepository &&
        (mediaAttachmentRepo as DirectMediaBlobCustodyRepository)
            .supportsDirectMediaBlobCustody) {
      try {
        final persistedBlobRows =
            await (mediaAttachmentRepo as DirectMediaBlobCustodyRepository)
                .loadDirectMediaBlobCustodyForMessage(resolvedMessageId);
        if (persistedBlobRows.any((row) => row.isLinkedFanoutRow)) {
          directLinkedMediaFanout =
              await _deriveLinkedMediaFanoutContextFromSurvivors(
                rows: persistedBlobRows,
                targetPeerId: targetPeerId,
                mediaAttachmentRepo: mediaAttachmentRepo,
              );
          if (directLinkedMediaFanout == null) {
            emitFlowEvent(
              layer: 'FL',
              event: 'CHAT_MSG_SEND_MEDIA_FANOUT_SINGULAR_REFUSED',
              details: {'id': shortenMessageId(resolvedMessageId)},
            );
            emitSendTiming(outcome: 'media_fanout_singular_refused');
            return (SendChatMessageResult.sendFailed, null);
          }
        }
      } catch (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'CHAT_MSG_SEND_MEDIA_FANOUT_AUTHORITY_READ_ERROR',
          details: {
            'id': shortenMessageId(resolvedMessageId),
            'errorType': error.runtimeType.toString(),
          },
        );
        emitSendTiming(outcome: 'media_fanout_authority_read_error');
        return (SendChatMessageResult.sendFailed, null);
      }
    }
    final candidates = normalizedAttachments ?? const <MediaAttachment>[];
    final candidateIds = candidates.map((attachment) => attachment.id).toSet();
    final allowPreparedPendingPath =
        attemptKind == OutgoingOrdinaryAttemptKind.existing &&
        existingOutgoing?.directMediaCustodyIntentId != null &&
        hasCompleteStrictBlobManifest;
    var preflightValid =
        candidates.isNotEmpty &&
        candidateIds.length == candidates.length &&
        !candidateIds.contains('') &&
        candidates.every(
          (attachment) => _isCompleteDirectMediaCustodyCandidate(
            attachment,
            messageId: resolvedMessageId,
            allowPreparedPendingPath: allowPreparedPendingPath,
          ),
        );

    if (attemptKind == OutgoingOrdinaryAttemptKind.fresh) {
      preflightValid = preflightValid && existingOutgoing == null;
    } else {
      try {
        final durableParent = await messageRepo.getMessage(resolvedMessageId);
        final durableAttachments = await mediaAttachmentRepo!
            .getAttachmentsForMessage(
              resolvedMessageId,
              owner: MediaOwnerLane.direct,
            );
        final durableIds = durableAttachments
            .map((attachment) => attachment.id)
            .toSet();
        final durableIntent = durableParent?.directMediaCustodyIntentId;
        final exactManifest =
            durableIds.length == durableAttachments.length &&
            durableIds.length == candidateIds.length &&
            durableIds.containsAll(candidateIds);
        final expectedIntent = durableIntent == null
            ? null
            : computeDirectMediaCustodyIntentId(
                messageId: resolvedMessageId,
                attachmentIds: durableIds,
              );
        final effectiveCreatedAt = createdAt ?? durableParent?.createdAt;
        preflightValid =
            preflightValid &&
            durableParent != null &&
            !durableParent.isIncoming &&
            durableParent.contactPeerId == targetPeerId &&
            durableParent.senderPeerId == senderPeerId &&
            durableParent.text == sanitizedText &&
            durableParent.timestamp == resolvedTimestamp &&
            durableParent.createdAt == effectiveCreatedAt &&
            durableParent.quotedMessageId == quotedMessageId &&
            durableParent.dedupKey == resolvedDedupKey &&
            durableParent.isForwarded == isForwarded &&
            const <String>{
              'sending',
              'failed',
            }.contains(durableParent.status) &&
            durableParent.editedAt == null &&
            durableParent.deletedAt == null &&
            durableParent.deletedByPeerId == null &&
            durableParent.hiddenAt == null &&
            durableParent.transport == null &&
            durableParent.wireEnvelope == null &&
            durableParent.relayExpiresAt == null &&
            durableParent.custodyCheckedAt == null &&
            // 358: the durable parent must carry EITHER the unchanged ordinary
            // shape or the exact authored disappearing shape. The sender-side
            // receiver-clock columns stay null in both: only the receiver
            // starts a disappearance clock.
            _isTokenBearingDirectMediaPreflightPolicy(
              durableParent,
              expected: effectivePrivateMediaPolicy,
            ) &&
            durableParent.privateMediaReceivedAtMs == null &&
            durableParent.privateMediaExpiresAtMs == null &&
            durableParent.privateMediaRevealedAtMs == null &&
            durableParent.privateMediaTerminalAtMs == null &&
            durableParent.privateMediaClockHighWaterMs == null &&
            durableIntent != null &&
            durableIntent == expectedIntent &&
            exactManifest &&
            _isExactPreparedDirectMediaPreflightProjection(
              messageId: resolvedMessageId,
              durable: durableAttachments,
              candidates: candidates,
              allowPreparedPendingPath: allowPreparedPendingPath,
            );
        if (preflightValid) existingOutgoing = durableParent;
      } catch (_) {
        preflightValid = false;
      }
    }

    if (!preflightValid) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_SEND_MEDIA_CUSTODY_PREFLIGHT_REFUSED',
        details: {'id': shortenMessageId(resolvedMessageId)},
      );
      emitSendTiming(outcome: 'media_custody_preflight_refused');
      return (SendChatMessageResult.sendFailed, null);
    }
  }

  // 301: a protected PHOTO send embeds one bounded inline thumbnail into the
  // serialized attachment map (the encrypted inner JSON), so the receiver can
  // render a restricted bubble thumbnail without any pre-open blob download.
  // The MediaAttachment model never carries the key; edits never touch it.
  final mediaJson = normalizedAttachments
      ?.map((attachment) => attachment.toJson())
      .toList();
  if (mediaJson != null &&
      effectivePrivateMediaPolicy.mode == PrivateMediaMode.protected &&
      action != MessagePayload.actionEdit &&
      normalizedAttachments!.length == 1) {
    final inlineThumbnail = await _generateProtectedPhotoInlineThumbnail(
      normalizedAttachments.single,
    );
    if (inlineThumbnail != null) {
      mediaJson[0] = {
        ...mediaJson[0],
        kProtectedPhotoInlineThumbnailKey: base64Encode(inlineThumbnail),
      };
    }
  }

  final payload = MessagePayload(
    id: resolvedMessageId,
    diagnosticTraceId: AppDiagnostics.instance.traceForOperation(
      'message:$resolvedMessageId',
    ),
    text: sanitizedText,
    senderPeerId: senderPeerId,
    senderUsername: senderUsername,
    timestamp: resolvedTimestamp,
    action: action,
    eventId: resolvedEventId,
    editedAt: resolvedEditedAt,
    quotedMessageId: effectiveQuotedMessageId,
    media: mediaJson,
    dedupKey: resolvedDedupKey,
    isForwarded: effectiveIsForwarded,
    privateMediaPolicy: effectivePrivateMediaPolicy,
  );
  logChatOutgoing(
    messageId: resolvedMessageId,
    toPeerId: targetPeerId,
    status: 'queued',
    text: sanitizedText,
  );

  // 366: initialized Protected/View-Once initials settle only through the
  // explicit private plural Barrier B. Supplying this context forbids every
  // scalar fallback: one malformed target, capability gap, or crossed parent
  // refuses before encryption/transport and leaves the v114 survivors intact.
  if (directPrivateMediaFanout != null) {
    if (!ownsDirectPrivateMediaInboxCustody ||
        !ownsDirectPrivateMediaFanout ||
        action != MessagePayload.actionSend ||
        !effectiveHasCompleteStrictBlobManifest ||
        normalizedAttachments == null ||
        normalizedAttachments.length != 1 ||
        existingOutgoing == null ||
        bridge == null ||
        directTextCustodyRepo == null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_SEND_PRIVATE_MEDIA_FANOUT_REFUSED',
        details: {
          'id': shortenMessageId(resolvedMessageId),
          'reason': 'ineligible_shape',
        },
      );
      emitSendTiming(outcome: 'private_media_fanout_shape_refused');
      return (SendChatMessageResult.sendFailed, null);
    }
    return _authorDirectPrivateMediaFanout(
      fanout: directPrivateMediaFanout,
      p2pService: p2pService,
      messageRepo: messageRepo,
      mediaAttachmentRepo: mediaAttachmentRepo!,
      directTextCustodyRepo: directTextCustodyRepo,
      storeInAckCustodyInboxDetailed: effectiveStoreInAckCustodyInboxDetailed,
      storeInMediaExpiryBoundedInboxDetailed:
          effectiveStoreInMediaExpiryBoundedInboxDetailed,
      bridge: bridge,
      targetPeerId: targetPeerId,
      senderPeerId: senderPeerId,
      senderUsername: senderUsername,
      payload: payload,
      expectedParent: existingOutgoing,
      completedAttachment: normalizedAttachments.single,
      resolvedMessageId: resolvedMessageId,
      onDirectTextCustodyStaged: onDirectTextCustodyStaged,
      emitSendTiming: emitSendTiming,
      recordMetrics: recordMetrics,
    );
  }

  // 362: a caller-proven linked-media fanout settles exclusively through the
  // plural v108 stage. Every mismatch fails closed here — after fanout
  // context was provided this send may NEVER demote to the singular stage.
  if (directLinkedMediaFanout != null) {
    if (!ownsDirectMediaInboxCustody ||
        replayedDirectMediaCustody != null ||
        isOutgoingPrivateOneMoreLook ||
        action != MessagePayload.actionSend ||
        !effectiveHasCompleteStrictBlobManifest ||
        normalizedAttachments == null ||
        normalizedAttachments.isEmpty ||
        existingOutgoing == null ||
        bridge == null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_SEND_MEDIA_FANOUT_REFUSED',
        details: {
          'id': shortenMessageId(resolvedMessageId),
          'reason': 'ineligible_shape',
        },
      );
      emitSendTiming(outcome: 'media_fanout_shape_refused');
      return (SendChatMessageResult.sendFailed, null);
    }
    return _authorDirectLinkedMediaFanout(
      fanout: directLinkedMediaFanout,
      p2pService: p2pService,
      messageRepo: messageRepo,
      mediaAttachmentRepo: mediaAttachmentRepo!,
      directTextCustodyRepo: directTextCustodyRepo,
      storeInAckCustodyInboxDetailed: effectiveStoreInAckCustodyInboxDetailed,
      storeInMediaExpiryBoundedInboxDetailed:
          effectiveStoreInMediaExpiryBoundedInboxDetailed,
      bridge: bridge,
      targetPeerId: targetPeerId,
      senderPeerId: senderPeerId,
      senderUsername: senderUsername,
      payload: payload,
      expectedParent: existingOutgoing,
      normalizedAttachments: normalizedAttachments,
      resolvedMessageId: resolvedMessageId,
      onDirectTextCustodyStaged: onDirectTextCustodyStaged,
      emitSendTiming: emitSendTiming,
      recordMetrics: recordMetrics,
    );
  }

  // 4. Serialize as v2 encrypted envelope.
  String jsonString;
  final exactReplay = replayedDirectMediaCustody;
  if (exactReplay != null) {
    // A committed v108 owner is already the immutable serialization
    // authority. A late media finalizer adopts those bytes before touching the
    // crypto bridge and must never route through a generic staging writer.
    jsonString = exactReplay.wireEnvelope;
  } else {
    try {
      AppDiagnostics.instance.record(
        feature: 'message',
        stage: 'encrypt',
        outcome: 'started',
        traceId: diagnosticTraceId,
      );
      final innerJson = payload.toInnerJson();
      final encryptStopwatch = Stopwatch()..start();
      final encryptResult = await callEncryptMessage(
        bridge: bridge!,
        recipientMlKemPublicKey: recipientKey!,
        plaintext: innerJson,
      );
      encryptStopwatch.stop();
      stepTimings['encryptMs'] = encryptStopwatch.elapsedMilliseconds;
      if (encryptResult['ok'] != true) {
        emitFlowEvent(
          layer: 'FL',
          event: 'CHAT_MSG_SEND_ENCRYPT_FAILED',
          details: {
            'errorCode': encryptResult['errorCode'],
            'errorMessage': encryptResult['errorMessage'],
          },
        );
        emitSendTiming(
          outcome: 'encrypt_failed',
          details: {'errorCode': encryptResult['errorCode']},
        );
        return (SendChatMessageResult.sendFailed, null);
      }
      AppDiagnostics.instance.record(
        feature: 'message',
        stage: 'encrypt',
        outcome: 'ok',
        traceId: diagnosticTraceId,
      );
      jsonString = MessagePayload.buildEncryptedEnvelope(
        id: resolvedMessageId,
        senderPeerId: senderPeerId,
        senderUsername: senderUsername,
        kem: encryptResult['kem'] as String,
        ciphertext: encryptResult['ciphertext'] as String,
        nonce: encryptResult['nonce'] as String,
        eventId: resolvedEventId,
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_SEND_ENCRYPT_ERROR',
        details: {'error': e.toString()},
      );
      emitSendTiming(outcome: 'encrypt_error');
      return (SendChatMessageResult.sendFailed, null);
    }
  }

  logChatWireEnvelope(
    direction: 'OUT',
    messageId: resolvedMessageId,
    wireJson: jsonString,
  );

  // SECTION 4 CONTRACT: the exact attempt and wireEnvelope are persisted
  // BEFORE the transport race. If the app crashes after this point, Section
  // 1's PendingMessageRetrier can replay the attempt without re-serializing or
  // re-encrypting.
  DirectInboxCustodyOutboxEntry? stagedDirectInboxCustody = exactReplay;
  DirectReactionInboxCustodyOutboxEntry? stagedDirectMutationInboxCustody;
  ConversationMessage? stagedCustodyMessage = replayedDirectMediaMessage;
  if (isOutgoingPrivateOneMoreLook) {
    final handoff = messageId == null
        ? const _OutgoingDirectPrivateHandoff.refused()
        : await _commitOutgoingDirectPrivateEnvelopeForTransport(
            messageId: messageId,
            envelope: jsonString,
            attachments: normalizedAttachments,
            messageRepo: messageRepo,
            mediaAttachmentRepo: mediaAttachmentRepo,
            wireMediaBlobManifestHash: ownsDirectPrivateMediaInboxCustody
                ? wireMediaBlobManifestHash
                : null,
            wireMediaBlobExpiresAtMs: ownsDirectPrivateMediaInboxCustody
                ? wireMediaBlobExpiresAtMs
                : null,
          );
    final handedOff = handoff.authorized;
    if (handedOff && ownsDirectPrivateMediaInboxCustody) {
      stagedDirectInboxCustody = handoff.custody;
      if (stagedDirectInboxCustody == null) {
        emitFlowEvent(
          layer: 'FL',
          event: 'CHAT_MSG_SEND_PRIVATE_ENVELOPE_HANDOFF_REFUSED',
          details: {
            'id': shortenMessageId(resolvedMessageId),
            'reason': 'missing_exact_custody_owner',
          },
        );
        emitSendTiming(outcome: 'private_envelope_handoff_refused');
        return (SendChatMessageResult.sendFailed, null);
      }
      // Replay only the exact winner's immutable bytes from this point on.
      jsonString = stagedDirectInboxCustody.wireEnvelope;
    }
    if (!handedOff) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_SEND_PRIVATE_ENVELOPE_HANDOFF_REFUSED',
        details: {
          'id': resolvedMessageId.length > 8
              ? resolvedMessageId.substring(0, 8)
              : resolvedMessageId,
        },
      );
      emitSendTiming(outcome: 'private_envelope_handoff_refused');
      return (SendChatMessageResult.sendFailed, null);
    }
  } else if (exactReplay == null) {
    final hasOrdinaryMedia = normalizedAttachments?.isNotEmpty ?? false;
    if (ordinaryMutationRepo == null ||
        (ownsDirectTextInboxCustody && directTextCustodyRepo == null) ||
        (ownsDirectTextMutationInboxCustody &&
            directMutationCustodyRepo == null) ||
        (ownsDirectMediaCaptionEditInboxCustody &&
            directMediaCaptionEditRepo == null) ||
        (hasOrdinaryMedia &&
            !ownsDirectMediaInboxCustody &&
            !ownsDirectMediaCaptionEditInboxCustody &&
            mediaAttachmentRepo is! OutgoingOrdinaryAttemptStagingRepository)) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_SEND_ATTEMPT_STAGE_REFUSED',
        details: {
          'id': resolvedMessageId.length > 8
              ? resolvedMessageId.substring(0, 8)
              : resolvedMessageId,
          'reason': ordinaryMutationRepo == null
              ? 'missing_message_capability'
              : ownsDirectTextInboxCustody && directTextCustodyRepo == null
              ? 'missing_direct_inbox_custody_capability'
              : ownsDirectTextMutationInboxCustody &&
                    directMutationCustodyRepo == null
              ? 'missing_direct_mutation_custody_capability'
              : ownsDirectMediaCaptionEditInboxCustody
              ? 'missing_media_caption_edit_capability'
              : 'missing_media_capability',
        },
      );
      emitSendTiming(outcome: 'attempt_stage_refused');
      return (SendChatMessageResult.sendFailed, null);
    }

    final expectedAttempt = attemptKind == OutgoingOrdinaryAttemptKind.fresh
        ? null
        : existingOutgoing;
    final stagedBase = payload.toConversationMessage(
      contactPeerId: targetPeerId,
      isIncoming: false,
      status: 'sending',
      createdAt: ownsDirectMediaCaptionEditInboxCustody
          ? existingOutgoing!.createdAt
          : attemptKind == OutgoingOrdinaryAttemptKind.fresh
          ? (createdAt ?? resolvedTimestamp)
          : (createdAt ?? existingOutgoing?.createdAt ?? resolvedTimestamp),
      editedAt: resolvedEditedAt,
      wireEnvelope: jsonString,
    );
    // Runtime-only ordinary/disappearing lifecycle fields are not authored by
    // this transport attempt. Preserve the exact observed values so staging's
    // full snapshot CAS detects crossed work without resetting them.
    final stagedAttempt = expectedAttempt == null
        ? stagedBase.copyWith(media: normalizedAttachments ?? const [])
        : stagedBase.copyWith(
            readAt: expectedAttempt.readAt,
            privateMediaState: expectedAttempt.privateMediaState,
            privateMediaReceivedAtMs: expectedAttempt.privateMediaReceivedAtMs,
            privateMediaExpiresAtMs: expectedAttempt.privateMediaExpiresAtMs,
            privateMediaRevealedAtMs: expectedAttempt.privateMediaRevealedAtMs,
            privateMediaTerminalAtMs: expectedAttempt.privateMediaTerminalAtMs,
            privateMediaClockHighWaterMs:
                expectedAttempt.privateMediaClockHighWaterMs,
            media: normalizedAttachments ?? const [],
          );
    try {
      final custodyIncarnationId = ownsDirectTextInboxCustody
          ? _uuid.v4().replaceAll('-', '')
          : null;
      late final OutgoingOrdinaryMutationOutcome stagedOutcome;
      late final ConversationMessage? stagedMessage;
      var stagedAuthorizesTransport = false;
      DirectInboxCustodyOutboxEntry? committedMediaCustody;
      DirectReactionInboxCustodyOutboxEntry? committedMutationCustody;
      if (ownsDirectTextInboxCustody) {
        final staged = await directTextCustodyRepo!
            .stageOutgoingDirectTextInboxCustody(
              expected: expectedAttempt,
              staged: stagedAttempt,
              kind: attemptKind,
              recipientPeerId: targetPeerId,
              incarnationId: custodyIncarnationId!,
              wireEnvelope: jsonString,
            );
        stagedOutcome = staged.outcome;
        stagedMessage = staged.message;
        stagedAuthorizesTransport = staged.authorizesTransport;
      } else if (ownsDirectTextMutationInboxCustody) {
        final staged = await directMutationCustodyRepo!
            .stageOutgoingDirectTextMutationInboxCustody(
              expected: expectedAttempt!,
              staged: stagedAttempt,
              kind: attemptKind,
              recipientPeerId: targetPeerId,
              eventId: resolvedEventId!,
              wireEnvelope: jsonString,
            );
        stagedOutcome = staged.outcome;
        stagedMessage = staged.message;
        stagedAuthorizesTransport = staged.authorizesTransport;
        committedMutationCustody = staged.custody;
      } else if (ownsDirectMediaCaptionEditInboxCustody) {
        final staged = await directMediaCaptionEditRepo!
            .stageOutgoingDirectMediaCaptionEditInboxCustody(
              expected: expectedAttempt!,
              staged: stagedAttempt,
              attachments: normalizedAttachments!,
              kind: attemptKind,
              recipientPeerId: targetPeerId,
              eventId: resolvedEventId!,
              wireEnvelope: jsonString,
            );
        stagedOutcome = staged.outcome;
        stagedMessage = staged.message;
        stagedAuthorizesTransport = staged.authorizesTransport;
        committedMutationCustody = staged.custody;
      } else if (ownsDirectMediaInboxCustody) {
        final staged = await directMediaCustodyRepo!
            .stageOutgoingDirectMediaInboxCustody(
              expected: expectedAttempt,
              staged: stagedAttempt,
              attachments: normalizedAttachments!,
              kind: attemptKind,
              recipientPeerId: targetPeerId,
              wireEnvelope: jsonString,
              wireMediaBlobManifestHash: wireMediaBlobManifestHash,
              wireMediaBlobExpiresAtMs: wireMediaBlobExpiresAtMs,
            );
        stagedOutcome = staged.outcome;
        stagedMessage = staged.message;
        stagedAuthorizesTransport = staged.authorizesTransport;
        committedMediaCustody = staged.custody;
      } else if (hasOrdinaryMedia) {
        final staged =
            await (mediaAttachmentRepo
                    as OutgoingOrdinaryAttemptStagingRepository)
                .stageOutgoingOrdinaryAttemptWithMedia(
                  messageMutationRepository: ordinaryMutationRepo,
                  expected: expectedAttempt,
                  staged: stagedAttempt,
                  attachments: normalizedAttachments!,
                  kind: attemptKind,
                );
        stagedOutcome = staged.outcome;
        stagedMessage = staged.message;
        stagedAuthorizesTransport = staged.authorizesTransport;
      } else {
        final staged = await ordinaryMutationRepo.stageOutgoingOrdinaryAttempt(
          expected: expectedAttempt,
          staged: stagedAttempt,
          kind: attemptKind,
        );
        stagedOutcome = staged.outcome;
        stagedMessage = staged.message;
        stagedAuthorizesTransport = staged.authorizesTransport;
      }
      if (!stagedAuthorizesTransport) {
        emitFlowEvent(
          layer: 'FL',
          event: 'CHAT_MSG_SEND_ATTEMPT_STAGE_REFUSED',
          details: {
            'id': resolvedMessageId.length > 8
                ? resolvedMessageId.substring(0, 8)
                : resolvedMessageId,
            'reason': stagedOutcome.name,
          },
        );
        emitSendTiming(
          outcome: 'attempt_stage_refused',
          details: {'reason': stagedOutcome.name},
        );
        return (SendChatMessageResult.sendFailed, null);
      }
      if (ownsDirectInboxCustody) {
        stagedCustodyMessage = stagedMessage;
        if (ownsDirectMutationInboxCustody) {
          stagedDirectMutationInboxCustody = committedMutationCustody;
          if (stagedDirectMutationInboxCustody == null) {
            throw StateError(
              'authorized mutation custody stage returned no exact owner',
            );
          }
          jsonString = stagedDirectMutationInboxCustody.wireEnvelope;
        } else {
          // The authorized atomic mutation is the authority boundary. Build the
          // immutable handle from those exact inputs instead of re-reading after
          // commit: a concurrent lifecycle drain may already have completed and
          // deleted the row, which must not turn a committed send into failure.
          stagedDirectInboxCustody = ownsDirectMediaInboxCustody
              ? committedMediaCustody
              : DirectInboxCustodyOutboxEntry(
                  recipientPeerId: targetPeerId,
                  messageId: resolvedMessageId,
                  incarnationId: custodyIncarnationId!,
                  wireEnvelope: jsonString,
                  retryCount: 0,
                  lastAttemptAt: null,
                  lastErrorCode: null,
                  createdAt: stagedAttempt.createdAt,
                  updatedAt: stagedAttempt.createdAt,
                );
          final exactCustody = stagedDirectInboxCustody;
          if (exactCustody == null) {
            throw StateError(
              'authorized custody stage returned no exact owner',
            );
          }
          // A competing prepared-media finalizer may have committed different
          // ciphertext first. From this point onward replay only the winner's
          // immutable bytes returned by the transaction.
          jsonString = exactCustody.wireEnvelope;
        }
        try {
          onDirectTextCustodyStaged?.call(resolvedMessageId);
        } catch (error) {
          // The atomic stage is already committed transport authority. An
          // optional observer may record UI provenance, but can never revoke
          // custody or prevent the transport attempt.
          emitFlowEvent(
            layer: 'FL',
            event: 'CHAT_MSG_DIRECT_INBOX_CUSTODY_STAGE_OBSERVER_ERROR',
            details: {
              'id': resolvedMessageId.length > 8
                  ? resolvedMessageId.substring(0, 8)
                  : resolvedMessageId,
              'errorType': error.runtimeType.toString(),
            },
          );
        }
      }
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_SEND_ATTEMPT_STAGE_ERROR',
        details: {
          'id': resolvedMessageId.length > 8
              ? resolvedMessageId.substring(0, 8)
              : resolvedMessageId,
          'errorType': error.runtimeType.toString(),
        },
      );
      emitSendTiming(outcome: 'attempt_stage_error');
      return (SendChatMessageResult.sendFailed, null);
    }
  }

  if (canStageCustodyBeforeNodeNotRunning) {
    ConversationMessage? authoritativeMessage = stagedCustodyMessage;
    try {
      if (ownsDirectPrivateMediaInboxCustody) {
        // The exact v108/v111 obligation is already durable. Node-off settles
        // only the private transport columns through their existing owner.
        authoritativeMessage =
            await _settleOutgoingDirectPrivateTransportState(
              messageRepo: messageRepo,
              mediaAttachmentRepo: mediaAttachmentRepo,
              attachments: normalizedAttachments,
              messageId: resolvedMessageId,
              expectedEnvelope: jsonString,
              status: 'failed',
              transport: null,
              relayExpiresAt: null,
            ) ??
            authoritativeMessage;
      } else {
        final settled = await ordinaryMutationRepo!
            .settleOutgoingOrdinaryTransport(
              messageId: resolvedMessageId,
              expectedContactPeerId: targetPeerId,
              expectedEnvelope: jsonString,
              status: 'failed',
              transport: null,
              relayExpiresAt: null,
              mode: OutgoingOrdinarySettlementMode.live,
            );
        authoritativeMessage =
            settled.outcome == OutgoingOrdinaryMutationOutcome.removed
            ? null
            : settled.message ?? authoritativeMessage;
      }
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_SEND_NODE_NOT_RUNNING_SETTLEMENT_ERROR',
        details: {
          'id': resolvedMessageId.length > 8
              ? resolvedMessageId.substring(0, 8)
              : resolvedMessageId,
          'errorType': error.runtimeType.toString(),
        },
      );
      try {
        // A successful null reload is authoritative physical removal. Retain
        // the staged fallback only when this diagnostic reload itself throws.
        authoritativeMessage = await messageRepo.getMessage(resolvedMessageId);
      } catch (_) {
        // The atomic stage already retained the exact message and outbox.
      }
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_NODE_NOT_RUNNING',
      details: const {'custodyStaged': true},
    );
    emitSendTiming(
      outcome: 'node_not_running',
      details: const {'custodyStaged': true},
    );
    return (SendChatMessageResult.nodeNotRunning, authoritativeMessage);
  }

  // LAN visibility is routing metadata, not delivery authority. Read it once
  // for discovery/inbox scheduling, but never use it to exclude an existing
  // authenticated target-Peer-ID stream from the reuse path below.
  final isLocalPeer = p2pService.isLocalPeer(targetPeerId);

  // 4.5. Check for existing connected peer first (connection reuse).
  // If the peer is already connected, try to send directly without
  // rediscovering — this is the fastest interactive path.
  final isAlreadyConnected = p2pService.currentState.connections.any(
    (c) => c.peerId == targetPeerId,
  );
  // FDC-02 (C1 resolution A): a peer whose ONLY live connection is a
  // `/p2p-circuit` must not reuse-short-circuit ahead of the race. The full race
  // preserves the independently staggered relay-LIVE proof opportunity. A peer
  // with any direct connection still uses the authenticated reuse fast path.
  final isCircuitOnlyConnected = _isCircuitOnlyConnected(
    p2pService,
    targetPeerId,
  );
  final isLiveConnected = p2pService.isConnectedToPeer(targetPeerId);
  final unknownPresence =
      !isAlreadyConnected && !isLocalPeer && !isLiveConnected;

  Future<void> settleAcceptedInboxCustody(InboxStoreOutcome outcome) async {
    ConversationMessage? observedMessage;
    try {
      if (ownsDirectPrivateMediaInboxCustody) {
        // 354: exact ACK-or-expiry acceptance is the only owner that may
        // retire this v108 incarnation and advance its bound v111 rows to
        // cleanup. The private settlement branch cannot bypass it.
        final custody = stagedDirectInboxCustody;
        if (custody == null) {
          throw StateError(
            'accepted private media custody has no staged local authority',
          );
        }
        final completion = await directTextCustodyRepo!
            .completeAcceptedDirectInboxCustodyIfExact(
              expected: custody,
              relayExpiresAt: outcome.expiresAtMs,
            );
        if (!completion.completed) {
          throw StateError(
            'private media custody completion did not converge: '
            '${completion.outcome.name}',
          );
        }
        observedMessage =
            completion.message ??
            await messageRepo.getMessage(resolvedMessageId);
      } else if (isOutgoingPrivateOneMoreLook) {
        observedMessage = await _settleOutgoingDirectPrivateTransportState(
          messageRepo: messageRepo,
          mediaAttachmentRepo: mediaAttachmentRepo,
          attachments: normalizedAttachments,
          messageId: resolvedMessageId,
          expectedEnvelope: jsonString,
          status: 'inboxed',
          transport: 'inbox',
          relayExpiresAt: outcome.expiresAtMs,
        );
      } else if (ownsDirectInboxCustody) {
        if (ownsDirectMutationInboxCustody) {
          final custody = stagedDirectMutationInboxCustody;
          if (custody == null) {
            throw StateError(
              'accepted mutation custody has no staged local authority',
            );
          }
          final completion = await directMutationLifecycleRepo!
              .completeAcceptedDirectTextMutationInboxCustodyIfExact(
                expected: custody,
                relayExpiresAt: outcome.expiresAtMs,
              );
          if (!completion.converged) {
            throw StateError(
              'mutation custody completion did not converge: ${completion.name}',
            );
          }
          observedMessage = await messageRepo.getMessage(resolvedMessageId);
        } else {
          final custody = stagedDirectInboxCustody;
          if (custody == null) {
            throw StateError('accepted custody has no staged local authority');
          }
          final completion = await directTextCustodyRepo!
              .completeAcceptedDirectInboxCustodyIfExact(
                expected: custody,
                relayExpiresAt: outcome.expiresAtMs,
              );
          observedMessage = completion.message;
        }
      } else {
        final settled = await ordinaryMutationRepo!
            .settleOutgoingOrdinaryTransport(
              messageId: resolvedMessageId,
              expectedContactPeerId: targetPeerId,
              expectedEnvelope: jsonString,
              status: 'inboxed',
              transport: 'inbox',
              relayExpiresAt: outcome.expiresAtMs,
              mode: OutgoingOrdinarySettlementMode.live,
            );
        observedMessage = settled.message;
      }
    } catch (error) {
      if (ownsDirectMutationInboxCustody &&
          stagedDirectMutationInboxCustody != null) {
        try {
          await directMutationLifecycleRepo!
              .recordDirectTextMutationInboxCustodyFailureIfExact(
                expected: stagedDirectMutationInboxCustody,
                errorCode:
                    DirectReactionInboxCustodyErrorCode.localCompletionFailed,
              );
        } catch (_) {
          // The exact row remains durable; a later lifecycle drain retries it.
        }
      } else if (ownsDirectInboxCustody && stagedDirectInboxCustody != null) {
        try {
          await directTextCustodyRepo!.recordDirectInboxCustodyFailureIfExact(
            expected: stagedDirectInboxCustody,
            errorCode: DirectInboxCustodyErrorCode.localCompletionFailed,
          );
        } catch (_) {
          // The exact row remains durable; a later lifecycle drain retries it.
        }
      }
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_SEND_CUSTODY_SETTLEMENT_ERROR',
        details: {
          'id': shortenMessageId(resolvedMessageId),
          'errorType': error.runtimeType.toString(),
        },
      );
      return;
    }

    // The guarded writer returns the authoritative row. A stronger live result
    // may already have won, in which case the weaker custody candidate was still
    // attempted but must not emit a false milestone.
    if (observedMessage?.status == 'inboxed' &&
        observedMessage?.transport == 'inbox') {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_SEND_CUSTODY_CONFIRMED',
        details: {
          'id': resolvedMessageId.substring(0, 8),
          'targetPeerId': targetPrefix,
        },
      );
    }
  }

  Future<InboxStoreOutcome> performInboxStoreCall() async {
    AppDiagnostics.instance.record(
      feature: 'message',
      stage: 'store',
      outcome: 'started',
      traceId: diagnosticTraceId,
      values: {'transport': 'relay'},
    );
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_CONCURRENT_INBOX_BEGIN',
      details: {
        'id': resolvedMessageId.substring(0, 8),
        'targetPeerId': targetPrefix,
      },
    );

    final inboxStopwatch = Stopwatch()..start();
    late InboxStoreOutcome outcome;
    var storeThrew = false;
    try {
      final ackCustodyStore = effectiveStoreInAckCustodyInboxDetailed;
      final mediaCustodyStore = effectiveStoreInMediaExpiryBoundedInboxDetailed;
      final detailedStore = effectiveStoreInInboxDetailed;
      final strictBlobExpiry = stagedDirectInboxCustody?.mediaBlobExpiresAtMs;
      if (ownsDirectInboxCustody &&
          strictBlobExpiry != null &&
          mediaCustodyStore != null) {
        outcome = await mediaCustodyStore(
          targetPeerId,
          jsonString,
          custodyExpiresAtOrBeforeMs: strictBlobExpiry,
          timeoutMs: interactiveInboxBudget.inMilliseconds,
        );
      } else if (ownsDirectInboxCustody && strictBlobExpiry != null) {
        outcome = const InboxStoreOutcome(
          status: InboxStoreStatus.failed,
          errorCode: 'MEDIA_EXPIRY_BOUNDED_STORE_UNAVAILABLE',
        );
      } else if (ownsDirectInboxCustody && ackCustodyStore != null) {
        outcome = await ackCustodyStore(
          targetPeerId,
          jsonString,
          custodyKind: ownsDirectMutationInboxCustody
              ? AckCustodyKind.directMutationV109
              : AckCustodyKind.directTextV108,
          timeoutMs: interactiveInboxBudget.inMilliseconds,
        );
      } else if (ownsDirectInboxCustody) {
        outcome = const InboxStoreOutcome(
          status: InboxStoreStatus.failed,
          errorCode: 'ACK_OR_EXPIRY_STORE_UNAVAILABLE',
        );
      } else if (detailedStore != null) {
        outcome = await detailedStore(
          targetPeerId,
          jsonString,
          timeoutMs: interactiveInboxBudget.inMilliseconds,
        );
      } else {
        final stored = await p2pService.storeInInbox(
          targetPeerId,
          jsonString,
          timeoutMs: interactiveInboxBudget.inMilliseconds,
        );
        outcome = InboxStoreOutcome(
          status: stored ? InboxStoreStatus.stored : InboxStoreStatus.failed,
          errorCode: stored ? null : 'STORE_RETURNED_FALSE',
        );
      }
      if (strictBlobExpiry != null &&
          outcome.ackOrExpiryAccepted &&
          (outcome.expiresAtMs == null ||
              outcome.expiresAtMs! <= 0 ||
              outcome.expiresAtMs! > strictBlobExpiry)) {
        outcome = const InboxStoreOutcome(
          status: InboxStoreStatus.failed,
          errorCode: 'MEDIA_EXPIRY_PROOF_INVALID',
        );
      }
    } catch (error) {
      storeThrew = true;
      outcome = InboxStoreOutcome(
        status: InboxStoreStatus.failed,
        errorCode: 'STORE_ERROR',
        errorMessage: error.runtimeType.toString(),
      );
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_SEND_INBOX_FALLBACK_ERROR',
        details: {'errorType': error.runtimeType.toString()},
      );
    } finally {
      inboxStopwatch.stop();
      stepTimings['inboxMs'] = inboxStopwatch.elapsedMilliseconds;
    }

    final custodyAccepted = ownsDirectInboxCustody
        ? outcome.ackOrExpiryAccepted
        : outcome.accepted;
    AppDiagnostics.instance.record(
      feature: 'message',
      stage: 'store',
      outcome: custodyAccepted ? 'ok' : 'failed',
      reason: custodyAccepted
          ? 'none'
          : outcome.status == InboxStoreStatus.rejectedFull
          ? 'quota_exceeded'
          : 'send_failed',
      traceId: diagnosticTraceId,
      values: {
        'transport': 'relay',
        'durationMs': inboxStopwatch.elapsedMilliseconds,
      },
    );
    transportMetrics?.recordAttempt(leg: 'inbox', succeeded: custodyAccepted);
    if (custodyAccepted) {
      await settleAcceptedInboxCustody(outcome);
    } else if (ownsDirectMutationInboxCustody &&
        stagedDirectMutationInboxCustody != null) {
      final errorCode = storeThrew
          ? DirectReactionInboxCustodyErrorCode.storeThrew
          : outcome.status == InboxStoreStatus.rejectedFull
          ? DirectReactionInboxCustodyErrorCode.storeRejectedFull
          : DirectReactionInboxCustodyErrorCode.storeFailed;
      try {
        await directMutationLifecycleRepo!
            .recordDirectTextMutationInboxCustodyFailureIfExact(
              expected: stagedDirectMutationInboxCustody,
              errorCode: errorCode,
            );
      } catch (_) {
        // Retention is already durable; failure metadata is best-effort here.
      }
    } else if (ownsDirectInboxCustody && stagedDirectInboxCustody != null) {
      final errorCode = storeThrew
          ? DirectInboxCustodyErrorCode.storeThrew
          : outcome.status == InboxStoreStatus.rejectedFull
          ? DirectInboxCustodyErrorCode.storeRejectedFull
          : DirectInboxCustodyErrorCode.storeFailed;
      try {
        await directTextCustodyRepo!.recordDirectInboxCustodyFailureIfExact(
          expected: stagedDirectInboxCustody,
          errorCode: errorCode,
        );
      } catch (_) {
        // Retention is already durable; failure metadata is best-effort here.
      }
    }
    return outcome;
  }

  final inboxHedge = _SendScopedInboxHedge(performInboxStoreCall);
  if (unknownPresence) {
    unawaited(inboxHedge.startOrJoin());
  } else {
    final remainingHedgeBudget =
        kConnectedPeerInboxHedgeBudget - sendStopwatch.elapsed;
    inboxHedge.schedule(
      remainingHedgeBudget.isNegative ? Duration.zero : remainingHedgeBudget,
    );
  }

  _RaceResult? priorWritten;

  if (isAlreadyConnected && !isCircuitOnlyConnected) {
    connectionReused = true;
    sendPath = 'reuse';
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_REUSE_CONNECTION',
      details: {'targetPeerId': targetPrefix},
    );
    var reuseWritten = false;
    try {
      final timeoutMs = liveDeadline.allocateCommittedSendTimeoutMs();
      if (timeoutMs != null) {
        final reuseSendStopwatch = Stopwatch()..start();
        final sendResult = await p2pService.sendMessageWithReply(
          targetPeerId,
          jsonString,
          timeoutMs: timeoutMs,
        );
        reuseSendStopwatch.stop();
        stepTimings = {
          'sendMs': reuseSendStopwatch.elapsedMilliseconds,
          if (sendResult.streamOpenMs != null)
            'streamOpenMs': sendResult.streamOpenMs!,
          if (sendResult.writeMs != null) 'writeMs': sendResult.writeMs!,
          if (sendResult.ackWaitMs != null) 'ackWaitMs': sendResult.ackWaitMs!,
        };
        reuseWritten = sendResult.sent;
        if (sendResult.sent) {
          final reuseVia = _resolveGoSendTransport(
            p2pService,
            targetPeerId,
            sendResult,
          );
          final reuseEvidence = _RaceResult.succeeded(
            via: reuseVia,
            explicitAck: sendResult.acked == true,
            authenticated: true,
            stepTimings: stepTimings,
          );
          if (reuseEvidence.provesDeviceDeliveryForCurrentProtocol) {
            if (!ownsDirectInboxCustody) {
              inboxHedge.cancelIfNotStarted();
            }
            transportMetrics?.recordAttempt(leg: 'reuse', succeeded: true);
            recordMetrics(transport: reuseVia, rung: 'reuse');
            return _completeSuccessfulSend(
              p2pService: p2pService,
              messageRepo: messageRepo,
              payload: payload,
              targetPeerId: targetPeerId,
              jsonString: jsonString,
              acknowledged: true,
              via: reuseVia,
              resolvedMessageId: resolvedMessageId,
              text: sanitizedText,
              createdAt: createdAt,
              editedAt: resolvedEditedAt,
              mediaAttachmentRepo: mediaAttachmentRepo,
              attachments: normalizedAttachments,
              isOutgoingPrivateOneMoreLook: isOutgoingPrivateOneMoreLook,
              sendStopwatch: sendStopwatch,
              emitTimingEvent: emitTimingEvent,
              inboxHedge: inboxHedge,
              requiresAckOrExpiryCustody: ownsDirectInboxCustody,
              extraTimingDetails: {
                'connectionReused': true,
                'sendPath': 'reuse',
                ...stepTimings,
              },
            );
          }
          priorWritten ??= reuseEvidence;
        }
      }
    } catch (_) {
      // Connection reuse failed — fall through to race
    }
    // A completed write remains useful attempt telemetry, but only an explicit
    // affirmative ACK from this authenticated libp2p stream may short-circuit
    // and mint delivery. Written/uncommitted reuse falls through to the race.
    transportMetrics?.recordAttempt(leg: 'reuse', succeeded: reuseWritten);
    connectionReused = false;
    sendPath = 'unknown';
    stepTimings = {};
  }

  // 5. Race: local WiFi and direct discover/dial/send in parallel.
  // The first authenticated commitment settles. Earlier written-only evidence
  // remains available to the inbox/retry funnel if no live leg proves delivery.
  // (`isLocalPeer` is read above the reuse block — FDC-04 RC2 hoist.)

  // NET-REL-05 P3 (sticky transport): the last-known-good LIVE transport for
  // this peer, or null if none/expired/stale. Returning non-null is a VALIDITY
  // guarantee, not a hint: `lastKnownGoodTransport` only survives if the entry
  // is within TTL AND (for 'local') the peer is still LAN-visible, and the
  // P2PServiceImpl invalidation paths (disconnect / relay-health transition /
  // addresses-updated) drop the entry the moment the path could have gone stale
  // (see p2p_service_learned_transport_invalidation_test.dart). That guarantee
  // is what lets the SHORT-CIRCUIT below skip discover/dial entirely. Reading it
  // never blocks: null (expired/stale/absent) degenerates to the full cold race,
  // identical to today, so a stale/dead preference can never trap the send.
  final learned = p2pService.lastKnownGoodTransport(targetPeerId);
  // A learned local label identifies only the unauthenticated WebSocket route,
  // so it may not short-circuit authenticated work. Learned direct/relay paths
  // still reuse a target-Peer-ID stream, including when mDNS also sees the peer.
  if (learned == 'direct' || learned == 'relay') {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_STICKY_TRANSPORT',
      details: {'targetPeerId': targetPrefix, 'learned': learned},
    );

    // NET-REL-05 P3 short-circuit: a fresh+valid learned authenticated transport
    // lets us REUSE the known-good direct/relay path via sendMessageWithReply,
    // WITHOUT re-paying discovery/dial. This is
    // the only place that skips discover/dial on a NON-connected peer; it is
    // gated behind the now-tested invalidation so a stale entry never reaches
    // here. On ANY miss/failure of this attempt we fall THROUGH to today's full
    // PARALLEL race (NOT a serial try-then-timeout-then-race), so the unhappy
    // path is never slower than a cold send.
    final shortCircuit = await _tryLearnedShortCircuit(
      p2pService,
      targetPeerId,
      jsonString,
      learned: learned!,
      liveDeadline: liveDeadline,
      transportMetrics: transportMetrics,
    );
    if (shortCircuit != null &&
        shortCircuit.provesDeviceDeliveryForCurrentProtocol) {
      if (!ownsDirectInboxCustody) {
        inboxHedge.cancelIfNotStarted();
      }
      sendPath = 'sticky';
      stepTimings = shortCircuit.stepTimings;
      // The sticky short-circuit reuses the learned known-good path WITHOUT
      // re-discovery/dial — the same census semantics as connection 'reuse', so
      // it lands in the 'reuse' rung. The 'sticky' label is preserved in the
      // FLOW timing/observability event below (sendPath) for diagnosis.
      recordMetrics(transport: shortCircuit.via, rung: 'reuse');
      return _completeSuccessfulSend(
        p2pService: p2pService,
        messageRepo: messageRepo,
        payload: payload,
        targetPeerId: targetPeerId,
        jsonString: jsonString,
        acknowledged: true,
        via: shortCircuit.via!,
        resolvedMessageId: resolvedMessageId,
        text: sanitizedText,
        createdAt: createdAt,
        editedAt: resolvedEditedAt,
        mediaAttachmentRepo: mediaAttachmentRepo,
        attachments: normalizedAttachments,
        isOutgoingPrivateOneMoreLook: isOutgoingPrivateOneMoreLook,
        sendStopwatch: sendStopwatch,
        emitTimingEvent: emitTimingEvent,
        inboxHedge: inboxHedge,
        requiresAckOrExpiryCustody: ownsDirectInboxCustody,
        extraTimingDetails: {
          'connectionReused': false,
          'sendPath': 'sticky',
          'learned': learned,
          ...shortCircuit.stepTimings,
        },
      );
    }
    if (shortCircuit != null && shortCircuit.written) {
      priorWritten ??= shortCircuit;
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_STICKY_FALLBACK',
      details: {
        'targetPeerId': targetPrefix,
        'learned': learned,
        'reason': shortCircuit?.reason ?? 'unknown',
      },
    );
  }

  // 187: when the 183 keepalive has latched this ACTIVE peer as dropped, the
  // direct discover/dial WAN leg to it is doomed — it burns ~1.5 s dialing a
  // peer that cannot answer while the concurrent durable inbox (started above) has
  // already secured custody. Skip ONLY that WAN leg (Option A: the leg stays in
  // raceFutures[1], short-circuited at its top — LAN leg + inbox untouched).
  // Gated on [unknownPresence] so a connected/local/reachable peer (which took
  // the reuse fast path above or has a live conn) is NEVER skipped, keeping the
  // FDC-01/02 budget ladder intact for every non-dropped peer. Consulted via the
  // off-base [PeerDropSignal] capability so the ~31 base-P2PService fakes are
  // untouched; a service that doesn't implement it degrades to "never skip".
  final directSkipForKeepaliveDrop =
      unknownPresence &&
      p2pService is PeerDropSignal &&
      (p2pService as PeerDropSignal).isPeerSuspectedDropped(targetPeerId);

  // FDC-02 §6.2a/b: the staggered relay-LIVE leg joins the race only when a live
  // `/p2p-circuit` exists for the peer AND the payload may ride a limited live
  // relay socket (the complete UTF-8 envelope fits
  // [kLiveRelayMaxPayloadBytes]). Otherwise the race is the existing LAN+direct
  // pair and an all-fail send falls to the durable inbox (relay-INBOX, FDC-03
  // territory) — never the live relay socket. UTF-8 encoding stays short-circuited
  // behind the existing-circuit check so ineligible peers pay no second encode.
  final liveRelayEligible =
      _hasLiveCircuitConnection(p2pService, targetPeerId) &&
      _liveRelayEligible(utf8.encode(jsonString).length);

  // Build race futures
  final raceFutures = <Future<_RaceResult>>[];

  // Local WiFi path (bounded by interactiveLocalBudget). Added unconditionally:
  // when the peer is not yet in the discovered map we run a bounded
  // discover-on-send resolve first, so a cold-open same-WiFi peer can still
  // join the race within budget. If the peer is genuinely not on the LAN the
  // resolve times out to false and the parallel direct leg carries the message
  // (negative control: transport never becomes 'local').
  raceFutures.add(
    _tryLocalSendWithDiscovery(
      p2pService,
      targetPeerId,
      jsonString,
      senderPeerId,
      alreadyLocal: isLocalPeer,
      budget: interactiveLocalBudget,
      transportMetrics: transportMetrics,
    ).timeout(
      interactiveLocalBudget,
      onTimeout: () => _RaceResult.failed('local_discover_timeout'),
    ),
  );

  // Direct discover/dial/send path (bounded by interactiveDirectBudget).
  // Records its own attempt outcome inside the helper (at each terminal
  // return): the race completes on the first success, so a losing direct leg
  // may still be pending here and the caller cannot observe its result. The
  // outer timeout below does not record — the inner future resolves via its own
  // per-step budgets and records the real outcome exactly once (slightly later
  // on a slow path, which is fine for an aggregate session counter).
  raceFutures.add(
    _tryDirectSend(
      p2pService,
      targetPeerId,
      jsonString,
      liveDeadline: liveDeadline,
      transportMetrics: transportMetrics,
      // 187: when set, the direct leg short-circuits BEFORE discover/dial (the
      // leg stays present so the race's pending-count/failure classification is
      // undisturbed — Option A).
      skipForKeepaliveDrop: directSkipForKeepaliveDrop,
    ).timeout(
      // FDC-01: the OUTER cap is the aggregate (serial) ceiling, decoupled from
      // the per-step budget so a slow-but-progressing step can't be starved.
      // When it does fire the leg is genuinely stuck mid-progress on an online
      // peer, so the aggregate direct_timeout retains relay eligibility as
      // failure-classification plumbing. It does not launch another serial
      // recovery step; FDC-02's relay-live leg already participates in-race.
      liveDeadline.remaining,
      onTimeout: () =>
          _RaceResult.failed('direct_timeout', relayProbeEligible: true),
    ),
  );

  // Delivery authority is independent of route rank. The first result backed
  // by both the target Peer ID's authenticated libp2p stream and an explicit
  // affirmative ACK settles immediately. A WebSocket write (including its
  // nonce-correlated committed ACK) and an unacked libp2p write remain useful
  // transport evidence, but only for the existing inbox/retry funnel after all
  // eligible live legs have had their chance.
  final completer = Completer<_RaceResult>();
  final failures = <_RaceResult>[];
  _RaceResult? firstWritten = priorWritten;

  // FDC-02: the staggered relay-LIVE leg, added as a THIRD race future so it is
  // counted in [pendingCount] below (C4) — a fast LAN+direct DOUBLE failure
  // therefore cannot settle the race as failed before the relay penalty elapses
  // and the leg has had its chance (§6.2a / TC-02-02). It starts kRelayLegStagger
  // behind the LAN/direct legs (the penalty) and is suppressed only after an
  // authenticated explicit ACK has already completed the race. Written-only
  // evidence must not prevent the stronger relay proof from starting.
  if (liveRelayEligible) {
    raceFutures.add(
      Future<_RaceResult>(() async {
        await Future<void>.delayed(kRelayLegStagger);
        if (completer.isCompleted) {
          return _RaceResult.failed('relay_live_suppressed');
        }
        return _tryRelayLiveSend(
          p2pService,
          targetPeerId,
          jsonString,
          liveDeadline: liveDeadline,
          transportMetrics: transportMetrics,
        );
      }),
    );
  }

  var pendingCount = raceFutures.length;

  void completeWithFailure() {
    if (completer.isCompleted) return;
    var failureReason = failures.isNotEmpty
        ? failures.first.reason ?? 'unknown'
        : 'unknown';
    var relayProbeEligible = false;
    for (final failure in failures) {
      if (failure.relayProbeEligible) {
        failureReason = failure.reason ?? failureReason;
        relayProbeEligible = true;
        break;
      }
    }
    completer.complete(
      _RaceResult.failed(failureReason, relayProbeEligible: relayProbeEligible),
    );
  }

  // Wire each leg. A proving result wins immediately. Written-only results are
  // retained without suppressing any remaining authenticated attempt.
  for (final raceFuture in raceFutures) {
    void onResolved(_RaceResult result) {
      AppDiagnostics.instance.record(
        feature: 'message',
        stage: 'send',
        outcome: result.provesDeviceDeliveryForCurrentProtocol
            ? 'ok'
            : result.written
            ? 'pending'
            : 'failed',
        reason: result.written ? 'none' : 'send_failed',
        traceId: diagnosticTraceId,
        values: {
          'acknowledged': result.provesDeviceDeliveryForCurrentProtocol,
          'transport': result.via == 'relay'
              ? 'relay'
              : result.via == null
              ? 'unknown'
              : 'direct',
        },
      );
      pendingCount--;
      if (result.provesDeviceDeliveryForCurrentProtocol) {
        if (!completer.isCompleted) {
          if (!ownsDirectInboxCustody) {
            inboxHedge.cancelIfNotStarted();
          }
          completer.complete(result);
        }
        return;
      }
      if (result.written) {
        firstWritten ??= result;
      } else {
        failures.add(result);
      }
      if (pendingCount <= 0 && !completer.isCompleted) {
        if (firstWritten case final written?) {
          completer.complete(written);
        } else {
          completeWithFailure();
        }
      }
    }

    raceFuture
        .then(onResolved)
        .catchError((Object e) => onResolved(_RaceResult.failed(e.toString())));
  }

  // Presence is best-effort cache/telemetry advice. Defer it to the event queue
  // only after every eligible live future has been constructed and wired, so
  // synchronous lookup work cannot delay live launch or settlement. Timeout and
  // lookup errors both degrade to unknown and never escape the detached task.
  if (unknownPresence) {
    final presenceLookup = p2pService is RelayPresenceLookup
        ? p2pService as RelayPresenceLookup
        : null;
    unawaited(
      Future<void>(() async {
        var presenceEmphasis = RelayPresence.unknown;
        try {
          if (presenceLookup != null) {
            presenceEmphasis = await presenceLookup
                .lookupRelayPresence(targetPeerId)
                .timeout(
                  _presenceHintBudget,
                  onTimeout: () => RelayPresence.unknown,
                );
          }
        } catch (_) {
          presenceEmphasis = RelayPresence.unknown;
        }
        emitFlowEvent(
          layer: 'FL',
          event: 'CHAT_MSG_PRESENCE_EMPHASIS',
          details: {
            'id': resolvedMessageId.substring(0, 8),
            'targetPeerId': targetPrefix,
            'presence': presenceEmphasis.name,
          },
        );
      }),
    );
  }

  final raceResult = await completer.future;

  if (raceResult.success) {
    sendPath = raceResult.via == 'local' ? 'local' : 'direct';
    stepTimings = raceResult.stepTimings;
    recordMetrics(transport: raceResult.via, rung: sendPath);
    return _completeSuccessfulSend(
      p2pService: p2pService,
      messageRepo: messageRepo,
      payload: payload,
      targetPeerId: targetPeerId,
      jsonString: jsonString,
      acknowledged: raceResult.provesDeviceDeliveryForCurrentProtocol,
      via: raceResult.via!,
      resolvedMessageId: resolvedMessageId,
      text: sanitizedText,
      createdAt: createdAt,
      editedAt: resolvedEditedAt,
      mediaAttachmentRepo: mediaAttachmentRepo,
      attachments: normalizedAttachments,
      isOutgoingPrivateOneMoreLook: isOutgoingPrivateOneMoreLook,
      sendStopwatch: sendStopwatch,
      emitTimingEvent: emitTimingEvent,
      inboxHedge: inboxHedge,
      requiresAckOrExpiryCustody: ownsDirectInboxCustody,
      extraTimingDetails: {
        'connectionReused': false,
        'sendPath': sendPath,
        ...stepTimings,
      },
    );
  }

  var failureReason = raceResult.reason ?? 'unknown';

  // Persist a durable-custody (inbox) acceptance. Shared by the
  // concurrent-fallback short-circuit below and the sequential inbox tail so
  // the terminal `recordMetrics(rung:'inbox')` and status write stay identical
  // and fire exactly once. Relay-inbox acceptance is CUSTODY, not delivery
  // (doc 115): the row persists non-terminal 'inboxed' with the wire envelope
  // RETAINED so the custody sweep can re-store and a delivery receipt can
  // flip it to 'delivered'.
  Future<(SendChatMessageResult, ConversationMessage?)> persistInboxAccepted({
    int? expiresAtMs,
  }) async {
    sendPath = 'inbox';
    recordMetrics(transport: 'inbox', rung: 'inbox');
    final inboxedMessage = payload
        .toConversationMessage(
          contactPeerId: targetPeerId,
          isIncoming: false,
          status: 'inboxed',
          createdAt: createdAt,
          editedAt: resolvedEditedAt,
          transport: 'inbox',
          wireEnvelope: jsonString,
        )
        .copyWith(relayExpiresAt: expiresAtMs);
    final persistedMessage = await _persistOutgoingTransportState(
      messageRepo: messageRepo,
      message: inboxedMessage,
      attachments: normalizedAttachments,
      mediaAttachmentRepo: mediaAttachmentRepo,
      isOutgoingPrivateOneMoreLook: isOutgoingPrivateOneMoreLook,
      expectedEnvelope: jsonString,
      expectedContactPeerId: targetPeerId,
    );
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_SUCCESS',
      details: {
        'id': resolvedMessageId.substring(0, 8),
        'status': 'inboxed',
        'via': 'inbox',
      },
    );
    emitSendTiming(
      outcome: 'success',
      details: {'status': 'inboxed', 'via': 'inbox'},
    );
    logChatOutgoing(
      messageId: resolvedMessageId,
      toPeerId: targetPeerId,
      status: 'inboxed',
      text: sanitizedText,
    );
    _recordSuccessfulSendReadinessProof(
      p2pService,
      persistedMessage ?? inboxedMessage,
    );
    return (
      SendChatMessageResult.success,
      isOutgoingPrivateOneMoreLook
          ? persistedMessage?.copyWith(media: normalizedAttachments ?? const [])
          : persistedMessage,
    );
  }

  Future<(SendChatMessageResult, ConversationMessage?)>
  persistInboxRejectedFull() async {
    sendPath = 'inbox';
    recordMetrics(transport: null, rung: 'failed');
    final sentMessage = payload.toConversationMessage(
      contactPeerId: targetPeerId,
      isIncoming: false,
      status: 'sent',
      createdAt: createdAt,
      editedAt: resolvedEditedAt,
      transport: 'inbox',
      wireEnvelope: jsonString,
    );
    final persistedMessage = await _persistOutgoingTransportState(
      messageRepo: messageRepo,
      message: sentMessage,
      attachments: normalizedAttachments,
      mediaAttachmentRepo: mediaAttachmentRepo,
      isOutgoingPrivateOneMoreLook: isOutgoingPrivateOneMoreLook,
      expectedEnvelope: jsonString,
      expectedContactPeerId: targetPeerId,
    );
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_INBOX_FULL_RETRYABLE',
      details: {'id': resolvedMessageId.substring(0, 8), 'via': 'inbox'},
    );
    emitSendTiming(
      outcome: 'retryable',
      details: {'status': 'sent', 'via': 'inbox', 'errorCode': 'INBOX_FULL'},
    );
    logChatOutgoing(
      messageId: resolvedMessageId,
      toPeerId: targetPeerId,
      status: 'sent',
      text: sanitizedText,
    );
    return (
      SendChatMessageResult.success,
      isOutgoingPrivateOneMoreLook
          ? persistedMessage?.copyWith(media: normalizedAttachments ?? const [])
          : persistedMessage,
    );
  }

  // FDC-03 (invariant 4 — "no serial relay-probe carrier"): the SERIAL
  // relay-probe→inbox tail is REMOVED. Live relay recovery is now FDC-02's
  // IN-RACE staggered relay-live leg. Every all-failed path force-starts or joins
  // the same send-scoped hedge, disarming any delayed timer before the store.

  // All active paths failed — force durable custody now rather than waiting for
  // the delayed bound.
  emitFlowEvent(
    layer: 'FL',
    event: 'CHAT_MSG_SEND_RACE_ALL_FAILED',
    details: {'reason': failureReason},
  );

  var inboxOutcome = await inboxHedge.startOrJoin();
  if (inboxOutcome.status == InboxStoreStatus.failed) {
    inboxOutcome = await inboxHedge.retryAfterFailure();
  }
  if (ownsDirectInboxCustody
      ? inboxOutcome.ackOrExpiryAccepted
      : inboxOutcome.accepted) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_CONCURRENT_INBOX_CUSTODY',
      details: {
        'id': resolvedMessageId.substring(0, 8),
        'reason': failureReason,
      },
    );
    return persistInboxAccepted(expiresAtMs: inboxOutcome.expiresAtMs);
  }
  if (inboxOutcome.status == InboxStoreStatus.rejectedFull) {
    return persistInboxRejectedFull();
  }

  // Inbox fallback failed — persist with failed status.
  final failedMessage = payload.toConversationMessage(
    contactPeerId: targetPeerId,
    isIncoming: false,
    status: 'failed',
    createdAt: createdAt,
    editedAt: resolvedEditedAt,
    wireEnvelope: jsonString,
  );
  final persistedFailedMessage = await _persistOutgoingTransportState(
    messageRepo: messageRepo,
    message: failedMessage,
    attachments: normalizedAttachments,
    mediaAttachmentRepo: mediaAttachmentRepo,
    isOutgoingPrivateOneMoreLook: isOutgoingPrivateOneMoreLook,
    expectedEnvelope: jsonString,
    expectedContactPeerId: targetPeerId,
  );

  // Each failed real store call was counted by the send-scoped operation.
  recordMetrics(transport: null, rung: 'failed');

  emitFlowEvent(
    layer: 'FL',
    event: 'CHAT_MSG_SEND_FAILED',
    details: {'id': resolvedMessageId.substring(0, 8), 'reason': failureReason},
  );
  emitSendTiming(
    outcome: 'failed',
    details: {
      'reason': failureReason,
      'result': _resultForFailureReason(failureReason).name,
    },
  );
  logChatOutgoing(
    messageId: resolvedMessageId,
    toPeerId: targetPeerId,
    status: 'failed',
    text: sanitizedText,
  );
  return (
    _resultForFailureReason(failureReason),
    isOutgoingPrivateOneMoreLook
        ? persistedFailedMessage?.copyWith(
            media: normalizedAttachments ?? const [],
          )
        : persistedFailedMessage,
  );
}

Future<(SendChatMessageResult, ConversationMessage?)> editChatMessage({
  required P2PService p2pService,
  required MessageRepository messageRepo,
  required ConversationMessage originalMessage,
  required String updatedText,
  required String senderUsername,
  Bridge? bridge,
  String? recipientMlKemPublicKey,
  MediaAttachmentRepository? mediaAttachmentRepo,
  bool emitTimingEvent = true,
  TransportMetrics? transportMetrics,
  DirectEventFanoutAuthoring? directEventFanout,
}) {
  if (originalMessage.isIncoming) {
    return Future.value((SendChatMessageResult.invalidMessage, null));
  }
  if (originalMessage.status == 'failed') {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_EDIT_INVALID',
      details: {'reason': 'failed_message_requires_retry'},
    );
    return Future.value((SendChatMessageResult.invalidMessage, null));
  }

  return sendChatMessage(
    p2pService: p2pService,
    messageRepo: messageRepo,
    targetPeerId: originalMessage.contactPeerId,
    text: updatedText,
    senderPeerId: originalMessage.senderPeerId,
    senderUsername: senderUsername,
    action: MessagePayload.actionEdit,
    messageId: originalMessage.id,
    timestamp: originalMessage.timestamp,
    createdAt: originalMessage.createdAt,
    quotedMessageId: originalMessage.quotedMessageId,
    dedupKey: originalMessage.dedupKey,
    isForwarded: originalMessage.isForwarded,
    mediaAttachments: originalMessage.media,
    privateMediaPolicy: originalMessage.privateMediaPolicy,
    mediaAttachmentRepo: mediaAttachmentRepo,
    bridge: bridge,
    recipientMlKemPublicKey: recipientMlKemPublicKey,
    emitTimingEvent: emitTimingEvent,
    transportMetrics: transportMetrics,
    directEventFanout: directEventFanout,
  );
}

String? _resolveStrictlyNewerEditedAt({
  required String? priorEditedAt,
  required String? requestedEditedAt,
}) {
  final requested = requestedEditedAt == null
      ? clock.now().toUtc()
      : DateTime.tryParse(requestedEditedAt)?.toUtc();
  if (requested == null) return null;
  if (priorEditedAt == null) return requested.toIso8601String();

  final prior = DateTime.tryParse(priorEditedAt)?.toUtc();
  if (prior == null) return null;
  try {
    final minimum = prior.add(const Duration(microseconds: 1));
    return (requested.isAfter(minimum) ? requested : minimum).toIso8601String();
  } on ArgumentError {
    return null;
  }
}

/// Internal result of a single send path in the race.
class _RaceResult {
  /// The complete frame left this sender.
  final bool written;

  /// The native result carried an explicit `acked == true` value.
  ///
  /// This deliberately does not use [SendMessageResult.acknowledged], whose
  /// reply inference remains available to unrelated compatibility callers.
  final bool explicitAck;

  /// The attempt used the target Peer ID's authenticated libp2p stream.
  final bool authenticated;
  final String? via;
  final String? reason;
  final bool relayProbeEligible;
  final Map<String, int> stepTimings;

  bool get success => written;

  /// Delivery proof for current-version peers using the production default-on
  /// deferred-ACK contract. The wire bytes alone cannot distinguish an older or
  /// force-disabled receiver, so this remains a private orchestration claim.
  bool get provesDeviceDeliveryForCurrentProtocol =>
      written && authenticated && explicitAck;

  const _RaceResult._({
    required this.written,
    this.explicitAck = false,
    this.authenticated = false,
    this.via,
    this.reason,
    this.relayProbeEligible = false,
    this.stepTimings = const {},
  });

  factory _RaceResult.succeeded({
    required String via,
    required bool explicitAck,
    required bool authenticated,
    Map<String, int> stepTimings = const {},
  }) => _RaceResult._(
    written: true,
    explicitAck: explicitAck,
    authenticated: authenticated,
    via: via,
    stepTimings: stepTimings,
  );

  factory _RaceResult.failed(
    String reason, {
    bool relayProbeEligible = false,
    Map<String, int> stepTimings = const {},
  }) => _RaceResult._(
    written: false,
    reason: reason,
    relayProbeEligible: relayProbeEligible,
    stepTimings: stepTimings,
  );
}

String _inferDirectVsRelayForConnectedPeer(
  P2PService p2pService,
  String peerId,
) {
  final hasRelayConnection = p2pService.currentState.connections.any(
    (connection) =>
        connection.peerId == peerId &&
        connection.multiaddrs.any(
          (multiaddr) => multiaddr.contains('/p2p-circuit'),
        ),
  );
  return hasRelayConnection ? 'relay' : 'direct';
}

String _resolveGoSendTransport(
  P2PService p2pService,
  String peerId,
  SendMessageResult sendResult,
) {
  final actualTransport = sendResult.transport;
  if (actualTransport != null && actualTransport.isNotEmpty) {
    return actualTransport;
  }

  return _inferDirectVsRelayForConnectedPeer(p2pService, peerId);
}

/// FDC-02: true when the peer has at least one live `/p2p-circuit` connection —
/// the relay-LIVE leg's eligibility precondition.
bool _hasLiveCircuitConnection(P2PService p2pService, String peerId) {
  return p2pService.currentState.connections.any(
    (c) =>
        c.peerId == peerId &&
        c.multiaddrs.any((m) => m.contains('/p2p-circuit')),
  );
}

/// FDC-02 (C1 resolution A): true when EVERY live connection to the peer is a
/// `/p2p-circuit` (relay-backed). Such a peer must not take the reuse fast path,
/// so the complete proof race, including the staggered relay-LIVE leg, remains
/// available. A peer with any direct (non-circuit) connection keeps the reuse
/// short-circuit; an ambiguous empty-multiaddr connection is treated as direct.
bool _isCircuitOnlyConnected(P2PService p2pService, String peerId) {
  final peerConns = p2pService.currentState.connections
      .where((c) => c.peerId == peerId)
      .toList();
  if (peerConns.isEmpty) return false;
  return peerConns.every(
    (c) =>
        c.multiaddrs.isNotEmpty &&
        c.multiaddrs.any((m) => m.contains('/p2p-circuit')),
  );
}

/// FDC-02/R5: encrypted envelopes at or below [kLiveRelayMaxPayloadBytes] may
/// traverse the live relay leg (the circuit-v2 socket is ~128KB-limited).
/// Oversized envelopes fall to LAN-live / direct-live / the durable inbox.
bool _liveRelayEligible(int payloadBytes) =>
    payloadBytes <= kLiveRelayMaxPayloadBytes;

/// FDC-02: the staggered relay-LIVE leg. Sends over the existing live connection
/// — Go selects the path (normally the `/p2p-circuit`, since this leg runs only
/// when one exists and no better leg has committed) and LABELS the result
/// (relay-opportunistic, not relay-forced). Fires the [RelayLiveSendObserver]
/// seam (no-op in production) right before the send so a host test can attribute
/// this otherwise-identical `sendMessageWithReply` to the relay-live leg (C2).
/// Reaching here means the suppress-on-early-win guard already passed, so the
/// leg actually sends.
Future<_RaceResult> _tryRelayLiveSend(
  P2PService p2pService,
  String targetPeerId,
  String jsonString, {
  required OutgoingLiveDeadline liveDeadline,
  TransportMetrics? transportMetrics,
}) async {
  final timeoutMs = liveDeadline.allocateCommittedSendTimeoutMs();
  if (timeoutMs == null) {
    return _RaceResult.failed('relay_live_deadline_exhausted');
  }
  if (p2pService case final RelayLiveSendObserver observer) {
    observer.noteRelayLiveSendStart();
  }
  try {
    final sendResult = await p2pService.sendMessageWithReply(
      targetPeerId,
      jsonString,
      timeoutMs: timeoutMs,
    );
    if (!sendResult.sent) {
      return _RaceResult.failed('relay_live_send_failed');
    }
    return _RaceResult.succeeded(
      via: _resolveGoSendTransport(p2pService, targetPeerId, sendResult),
      explicitAck: sendResult.acked == true,
      authenticated: true,
    );
  } on TimeoutException {
    return _RaceResult.failed('relay_live_timeout');
  } catch (e) {
    return _RaceResult.failed('relay_live_error:$e');
  }
}

/// Try sending via local WiFi, running a bounded discover-on-send resolve first
/// when the peer was not already in the discovered map.
///
/// Self-bounded to [budget] (the caller also `.timeout`-wraps it), so this leg
/// can never delay the unconditional direct leg beyond the local budget. A peer
/// genuinely not on the LAN resolves to false and returns a failed result —
/// the direct leg then wins and transport is never `local`.
Future<_RaceResult> _tryLocalSendWithDiscovery(
  P2PService p2pService,
  String targetPeerId,
  String jsonString,
  String senderPeerId, {
  required bool alreadyLocal,
  required Duration budget,
  TransportMetrics? transportMetrics,
}) async {
  final sw = Stopwatch()..start();
  if (!alreadyLocal) {
    final found = await p2pService.discoverLocalPeer(
      targetPeerId,
      timeout: budget,
    );
    if (!found) {
      transportMetrics?.recordAttempt(leg: 'local', succeeded: false);
      return _RaceResult.failed(
        'local_not_discovered',
        stepTimings: {'localDiscoverMs': sw.elapsedMilliseconds},
      );
    }
  }
  final remaining = budget.inMilliseconds - sw.elapsedMilliseconds;
  return _tryLocalSend(
    p2pService,
    targetPeerId,
    jsonString,
    senderPeerId,
    timeoutMs: remaining > 0 ? remaining : 1,
    transportMetrics: transportMetrics,
  );
}

/// Try sending via local WiFi.
Future<_RaceResult> _tryLocalSend(
  P2PService p2pService,
  String targetPeerId,
  String jsonString,
  String senderPeerId, {
  required int timeoutMs,
  TransportMetrics? transportMetrics,
}) async {
  final localStopwatch = Stopwatch()..start();
  final durableLanSender = p2pService is DurableLanSender
      ? p2pService as DurableLanSender
      : null;
  final (localSent, acknowledged, ackKind) = durableLanSender != null
      ? switch (await durableLanSender.sendLocalMessageDurable(
          targetPeerId,
          jsonString,
          senderPeerId,
          timeoutMs: timeoutMs,
        )) {
          LanSendAck.committed => (true, true, 'committed'),
          LanSendAck.legacyAck => (true, false, 'legacy'),
          LanSendAck.failed => (false, false, 'failed'),
        }
      : await () async {
          final sent = await p2pService.sendLocalMessage(
            targetPeerId,
            jsonString,
            senderPeerId,
            timeoutMs: timeoutMs,
          );
          return sent
              ? (true, false, 'bool_legacy')
              : (false, false, 'bool_failed');
        }();
  localStopwatch.stop();
  final timings = {'localSendMs': localStopwatch.elapsedMilliseconds};
  transportMetrics?.recordAttempt(leg: 'local', succeeded: localSent);
  emitFlowEvent(
    layer: 'FL',
    event: 'CHAT_MSG_SEND_LAN_ACK',
    details: {
      'targetPeerId': targetPeerId.length > 8
          ? targetPeerId.substring(0, 8)
          : targetPeerId,
      'kind': ackKind,
    },
  );
  if (localSent) {
    return _RaceResult.succeeded(
      via: 'local',
      explicitAck: acknowledged,
      authenticated: false,
      stepTimings: timings,
    );
  }
  return _RaceResult.failed('local_send_failed', stepTimings: timings);
}

/// NET-REL-05 P3 short-circuit: attempt the LEARNED transport directly, WITHOUT
/// re-paying discovery/dial, reusing the known-good path.
///
/// - `'direct'` / `'relay'`: send via [sendMessageWithReply] over the existing
///   known-good connection (no `discoverPeer` / `dialPeer`).
///
/// A learned `'local'` label is intentionally ineligible: it cannot distinguish
/// an authenticated libp2p path from the unauthenticated WebSocket transport.
/// Returns written/proof evidence for a reached authenticated attempt, or null
/// for an unrecognized/ineligible label. Self-bounded so a stalled learned path
/// cannot make the fallback slower than a cold send.
Future<_RaceResult?> _tryLearnedShortCircuit(
  P2PService p2pService,
  String targetPeerId,
  String jsonString, {
  required String learned,
  required OutgoingLiveDeadline liveDeadline,
  TransportMetrics? transportMetrics,
}) async {
  if (learned == 'direct' || learned == 'relay') {
    try {
      final timeoutMs = liveDeadline.allocateCommittedSendTimeoutMs();
      if (timeoutMs == null) {
        return _RaceResult.failed('sticky_deadline_exhausted');
      }
      final sw = Stopwatch()..start();
      final sendResult = await p2pService.sendMessageWithReply(
        targetPeerId,
        jsonString,
        timeoutMs: timeoutMs,
      );
      sw.stop();
      final timings = {
        'stickySendMs': sw.elapsedMilliseconds,
        if (sendResult.streamOpenMs != null)
          'streamOpenMs': sendResult.streamOpenMs!,
        if (sendResult.writeMs != null) 'writeMs': sendResult.writeMs!,
        if (sendResult.ackWaitMs != null) 'ackWaitMs': sendResult.ackWaitMs!,
      };
      // Sticky short-circuit = reuse of the learned known-good authenticated
      // path; censused under the 'reuse' leg (no separate sticky leg exists).
      transportMetrics?.recordAttempt(leg: 'reuse', succeeded: sendResult.sent);
      if (sendResult.sent) {
        return _RaceResult.succeeded(
          via: _resolveGoSendTransport(p2pService, targetPeerId, sendResult),
          explicitAck: sendResult.acked == true,
          authenticated: true,
          stepTimings: timings,
        );
      }
      return _RaceResult.failed('sticky_send_failed', stepTimings: timings);
    } catch (e) {
      transportMetrics?.recordAttempt(leg: 'reuse', succeeded: false);
      return _RaceResult.failed('sticky_send_error:$e');
    }
  }

  return null;
}

/// Try direct discover → dial → send path, recording one `direct` attempt
/// outcome for the transport census regardless of which leg ultimately wins the
/// race. Records exactly once, on the real outcome of the inner attempt.
Future<_RaceResult> _tryDirectSend(
  P2PService p2pService,
  String targetPeerId,
  String jsonString, {
  required OutgoingLiveDeadline liveDeadline,
  TransportMetrics? transportMetrics,
  bool skipForKeepaliveDrop = false,
}) async {
  // 187 (Option A): the 183 keepalive has latched this active peer as dropped —
  // the direct discover/dial leg would burn ~1.5 s on a peer that cannot answer
  // while the concurrent durable inbox already holds custody. Short-circuit
  // BEFORE any discover/dial AND before recording a 'direct' attempt (the leg
  // never actually attempted). The leg stays PRESENT in raceFutures[1], so the
  // pending-count/failure classification is untouched; it simply resolves fast
  // to a NON-eligible failure.
  // `relayProbeEligible:false` classifies a keepalive-dropped peer for durable
  // inbox custody; there is no separate conversation probe step. The distinct
  // discriminator event proves the skip fired for the KEEPALIVE-DROP reason
  // (not presence, not a budget timeout).
  if (skipForKeepaliveDrop) {
    final shortTarget = targetPeerId.length > 10
        ? '${targetPeerId.substring(0, 10)}…'
        : targetPeerId;
    emitFlowEvent(
      layer: 'FL',
      event: 'SEND_DIRECT_LEG_SKIPPED_KEEPALIVE_DROP',
      details: {'targetPeerId': shortTarget},
    );
    return _RaceResult.failed(
      'direct_skipped_keepalive_drop',
      relayProbeEligible: false,
    );
  }
  final result = await _tryDirectSendInner(
    p2pService,
    targetPeerId,
    jsonString,
    liveDeadline: liveDeadline,
  );
  transportMetrics?.recordAttempt(leg: 'direct', succeeded: result.success);
  return result;
}

Future<_RaceResult> _tryDirectSendInner(
  P2PService p2pService,
  String targetPeerId,
  String jsonString, {
  required OutgoingLiveDeadline liveDeadline,
}) async {
  final timings = <String, int>{};

  // Every native phase is allocated from the original send-entry T0. Discovery
  // and dial retain their caps; the committed send receives all usable
  // remaining time so the receiver's deferred ACK still has its reserve.
  final discoverTimeoutMs = liveDeadline.allocatePhaseTimeoutMs(
    outgoingDiscoverPhaseCap,
  );
  if (discoverTimeoutMs == null) {
    return _RaceResult.failed(
      'peer_not_found',
      relayProbeEligible: true,
      stepTimings: timings,
    );
  }
  final discoverStopwatch = Stopwatch()..start();
  final peer = await p2pService.discoverPeer(
    targetPeerId,
    timeoutMs: discoverTimeoutMs,
  );
  discoverStopwatch.stop();
  timings['discoverMs'] = discoverStopwatch.elapsedMilliseconds;
  if (peer == null) {
    return _RaceResult.failed(
      'peer_not_found',
      relayProbeEligible: true,
      stepTimings: timings,
    );
  }

  final dialTimeoutMs = liveDeadline.allocatePhaseTimeoutMs(
    outgoingDialPhaseCap,
  );
  if (dialTimeoutMs == null) {
    return _RaceResult.failed(
      'dial_failed',
      relayProbeEligible: true,
      stepTimings: timings,
    );
  }
  final dialStopwatch = Stopwatch()..start();
  final dialed = await p2pService.dialPeer(
    targetPeerId,
    addresses: peer.addresses,
    timeoutMs: dialTimeoutMs,
  );
  dialStopwatch.stop();
  timings['dialMs'] = dialStopwatch.elapsedMilliseconds;
  if (!dialed) {
    return _RaceResult.failed(
      'dial_failed',
      relayProbeEligible: true,
      stepTimings: timings,
    );
  }

  final sendTimeoutMs = liveDeadline.allocateCommittedSendTimeoutMs();
  if (sendTimeoutMs == null) {
    return _RaceResult.failed(
      'direct_timeout',
      relayProbeEligible: true,
      stepTimings: timings,
    );
  }
  final sendStepStopwatch = Stopwatch()..start();
  SendMessageResult? sendResult;
  var sendTimedOut = false;
  try {
    sendResult = await p2pService.sendMessageWithReply(
      targetPeerId,
      jsonString,
      timeoutMs: sendTimeoutMs,
    );
  } on TimeoutException {
    sendTimedOut = true;
  }
  sendStepStopwatch.stop();
  timings['sendMs'] = sendStepStopwatch.elapsedMilliseconds;
  if (sendTimedOut || sendResult == null) {
    return _RaceResult.failed(
      sendTimedOut ? 'direct_timeout' : 'send_failed',
      relayProbeEligible: sendTimedOut,
      stepTimings: timings,
    );
  }
  if (sendResult.streamOpenMs != null) {
    timings['streamOpenMs'] = sendResult.streamOpenMs!;
  }
  if (sendResult.writeMs != null) {
    timings['writeMs'] = sendResult.writeMs!;
  }
  if (sendResult.ackWaitMs != null) {
    timings['ackWaitMs'] = sendResult.ackWaitMs!;
  }
  if (!sendResult.sent) {
    return _RaceResult.failed('send_failed', stepTimings: timings);
  }

  return _RaceResult.succeeded(
    via: _resolveGoSendTransport(p2pService, targetPeerId, sendResult),
    explicitAck: sendResult.acked == true,
    authenticated: true,
    stepTimings: timings,
  );
}

/// Persists the only durable custody marker for a freshly rebuilt outgoing
/// protected/view-once envelope.
///
/// A canonical attachment can authorize a restart-shaped handoff directly.
/// A still-pending row can authorize it only while the shared mutation
/// coordinator owns the exact full completion fingerprint. The lifecycle lock
/// keeps that process-local ownership from being discarded between the check
/// and the DB helper's exact parent/attachment compare-and-set.
/// Plan 354 typed result of the private transport handoff.
///
/// [custody] is non-null only for a strict Barrier B commit/adoption; it is the
/// exact v108 owner returned by the same transaction.
final class _OutgoingDirectPrivateHandoff {
  const _OutgoingDirectPrivateHandoff({required this.authorized, this.custody});

  const _OutgoingDirectPrivateHandoff.refused()
    : authorized = false,
      custody = null;

  final bool authorized;
  final DirectInboxCustodyOutboxEntry? custody;
}

Future<_OutgoingDirectPrivateHandoff>
_commitOutgoingDirectPrivateEnvelopeForTransport({
  required String messageId,
  required String envelope,
  required List<MediaAttachment>? attachments,
  required MessageRepository messageRepo,
  required MediaAttachmentRepository? mediaAttachmentRepo,
  String? wireMediaBlobManifestHash,
  int? wireMediaBlobExpiresAtMs,
}) async {
  if (messageId.isEmpty ||
      envelope.isEmpty ||
      attachments == null ||
      attachments.length != 1 ||
      messageRepo is! OutgoingDirectPrivateEnvelopeCustodyRepository ||
      mediaAttachmentRepo is! OutgoingDirectPrivateMutationRepository) {
    return const _OutgoingDirectPrivateHandoff.refused();
  }
  final strictManifestHash = wireMediaBlobManifestHash;
  final strictManifestExpiry = wireMediaBlobExpiresAtMs;
  final ownsStrictInboxCustody =
      strictManifestHash != null && strictManifestExpiry != null;
  if ((strictManifestHash == null) != (strictManifestExpiry == null)) {
    return const _OutgoingDirectPrivateHandoff.refused();
  }
  final strictCustodyCapability =
      messageRepo is OutgoingDirectPrivateMediaInboxCustodyRepository
      ? messageRepo as OutgoingDirectPrivateMediaInboxCustodyRepository
      : null;
  if (ownsStrictInboxCustody &&
      strictCustodyCapability?.supportsOutgoingDirectPrivateMediaInboxCustody !=
          true) {
    // Capability absence for an already selected strict private attempt fails
    // closed before egress; it must never silently fall back.
    return const _OutgoingDirectPrivateHandoff.refused();
  }

  final completed = attachments.single.copyWith(
    messageId: messageId,
    ownerLane: MediaOwnerLane.direct,
  );
  late final String expectedPendingLocalPath;
  try {
    expectedPendingLocalPath =
        MediaFilePathConvention.relativePathForPendingUpload(
          messageId: messageId,
          attachmentId: completed.id,
          mime: completed.mime,
        );
  } catch (_) {
    return const _OutgoingDirectPrivateHandoff.refused();
  }
  final fingerprint = OutgoingDirectPrivateCompletionFingerprint.fromAttachment(
    completed,
    expectedPendingLocalPath: expectedPendingLocalPath,
  );
  if (!fingerprint.isStructurallyComplete) {
    return const _OutgoingDirectPrivateHandoff.refused();
  }

  final attachmentRepository = mediaAttachmentRepo!;
  final mutationRepository =
      mediaAttachmentRepo as OutgoingDirectPrivateMutationRepository;
  final coordinator =
      mutationRepository.outgoingDirectPrivateMutationCoordinator;
  final envelopeRepository =
      messageRepo as OutgoingDirectPrivateEnvelopeCustodyRepository;
  return coordinator.lifecycleLock.synchronized(completed.id, () async {
    final owned = await coordinator.loadOwnedCompletionFingerprint(
      messageId: messageId,
      attachmentId: completed.id,
      expectedPendingLocalPath: expectedPendingLocalPath,
    );
    final hasOwnedPendingCompletion = owned == fingerprint;

    if (!hasOwnedPendingCompletion) {
      // Restart recovery has no process token. It is safe only when the
      // hydrated durable row already carries the exact canonical fingerprint;
      // the DB compare-and-set repeats the same persisted-field check.
      final durable = await attachmentRepository.getAttachmentsForMessage(
        messageId,
        owner: MediaOwnerLane.direct,
      );
      if (durable.length != 1 ||
          !fingerprint.matchesHydratedAttachment(durable.single)) {
        return const _OutgoingDirectPrivateHandoff.refused();
      }
    }

    if (ownsStrictInboxCustody) {
      final result = await strictCustodyCapability!
          .commitOutgoingDirectPrivateWireEnvelopeWithInboxCustody(
            messageId: messageId,
            completedAttachment: completed,
            expectedPendingLocalPath: expectedPendingLocalPath,
            envelope: envelope,
            hasOwnedPendingCompletion: hasOwnedPendingCompletion,
            wireMediaBlobManifestHash: strictManifestHash,
            wireMediaBlobExpiresAtMs: strictManifestExpiry,
          );
      return result.authorizesTransport
          ? _OutgoingDirectPrivateHandoff(
              authorized: true,
              custody: result.custody,
            )
          : const _OutgoingDirectPrivateHandoff.refused();
    }

    final outcome = await envelopeRepository
        .commitOutgoingDirectPrivateWireEnvelope(
          messageId: messageId,
          completedAttachment: completed,
          expectedPendingLocalPath: expectedPendingLocalPath,
          envelope: envelope,
          hasOwnedPendingCompletion: hasOwnedPendingCompletion,
        );
    return _OutgoingDirectPrivateHandoff(
      authorized: outcome.authorizesTransport,
    );
  });
}

Future<ConversationMessage?> _settleOutgoingDirectPrivateTransportState({
  required MessageRepository messageRepo,
  required MediaAttachmentRepository? mediaAttachmentRepo,
  required List<MediaAttachment>? attachments,
  required String messageId,
  required String expectedEnvelope,
  required String status,
  required String? transport,
  required int? relayExpiresAt,
}) async {
  final outcome = await settleOutgoingDirectPrivateTransportUnderLifecycleLock(
    messageRepository: messageRepo,
    mediaAttachmentRepository: mediaAttachmentRepo,
    attachments: attachments,
    messageId: messageId,
    expectedEnvelope: expectedEnvelope,
    status: status,
    transport: transport,
    relayExpiresAt: relayExpiresAt,
  );
  if (!outcome.accepted) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_PRIVATE_TRANSPORT_SETTLEMENT_REFUSED',
      details: {
        'id': messageId.length > 8 ? messageId.substring(0, 8) : messageId,
        'status': status,
      },
    );
  }
  return messageRepo.getMessage(messageId);
}

Future<ConversationMessage?> _persistOutgoingTransportState({
  required MessageRepository messageRepo,
  required ConversationMessage message,
  required List<MediaAttachment>? attachments,
  required MediaAttachmentRepository? mediaAttachmentRepo,
  required bool isOutgoingPrivateOneMoreLook,
  required String expectedEnvelope,
  required String expectedContactPeerId,
}) async {
  if (isOutgoingPrivateOneMoreLook) {
    // Completion persistence was already authorized by the outgoing-private
    // coordinator. Post-network work owns message transport columns only.
    return _settleOutgoingDirectPrivateTransportState(
      messageRepo: messageRepo,
      mediaAttachmentRepo: mediaAttachmentRepo,
      attachments: attachments,
      messageId: message.id,
      expectedEnvelope: expectedEnvelope,
      status: message.status,
      transport: message.transport,
      relayExpiresAt: message.relayExpiresAt,
    );
  }
  if (messageRepo is! OutgoingTransportMutationRepository) return null;
  final mutationRepo = messageRepo as OutgoingTransportMutationRepository;
  final settled = await mutationRepo.settleOutgoingOrdinaryTransport(
    messageId: message.id,
    expectedContactPeerId: expectedContactPeerId,
    expectedEnvelope: expectedEnvelope,
    status: message.status,
    transport: message.transport,
    relayExpiresAt: message.relayExpiresAt,
    mode: OutgoingOrdinarySettlementMode.live,
  );
  return settled.message;
}

Future<(SendChatMessageResult, ConversationMessage?)> _completeSuccessfulSend({
  required P2PService p2pService,
  required MessageRepository messageRepo,
  required MessagePayload payload,
  required String targetPeerId,
  required String jsonString,
  required bool acknowledged,
  required String via,
  required String resolvedMessageId,
  required String text,
  required String? createdAt,
  required String? editedAt,
  required MediaAttachmentRepository? mediaAttachmentRepo,
  required List<MediaAttachment>? attachments,
  required bool isOutgoingPrivateOneMoreLook,
  required Stopwatch sendStopwatch,
  required bool emitTimingEvent,
  required _SendScopedInboxHedge inboxHedge,
  required bool requiresAckOrExpiryCustody,
  Map<String, dynamic> extraTimingDetails = const {},
}) async {
  final message = await _persistOutgoingSendResult(
    payload: payload,
    targetPeerId: targetPeerId,
    jsonString: jsonString,
    acknowledged: acknowledged,
    createdAt: createdAt,
    editedAt: editedAt,
    via: via,
    inboxHedge: inboxHedge,
    requiresAckOrExpiryCustody: requiresAckOrExpiryCustody,
  );
  final persistedMessage = await _persistOutgoingTransportState(
    messageRepo: messageRepo,
    message: message,
    attachments: attachments,
    mediaAttachmentRepo: mediaAttachmentRepo,
    isOutgoingPrivateOneMoreLook: isOutgoingPrivateOneMoreLook,
    expectedEnvelope: jsonString,
    expectedContactPeerId: targetPeerId,
  );
  final observedMessage = persistedMessage ?? message;
  AppDiagnostics.instance.record(
    feature: 'message',
    stage: 'send',
    outcome: acknowledged ? 'ok' : 'pending',
    traceId: payload.diagnosticTraceId,
    values: {
      'acknowledged': acknowledged,
      'transport': via == 'relay' || via == 'inbox' ? 'relay' : 'direct',
    },
  );
  AppDiagnostics.instance.record(
    feature: 'message',
    stage: 'commit',
    outcome: persistedMessage != null ? 'ok' : 'failed',
    reason: persistedMessage != null ? 'none' : 'authority_lost',
    traceId: payload.diagnosticTraceId,
    values: {'committed': persistedMessage != null},
  );
  emitFlowEvent(
    layer: 'FL',
    event: 'CHAT_MSG_SEND_SUCCESS',
    details: {
      'id': resolvedMessageId.substring(0, 8),
      'status': observedMessage.status,
      'via': observedMessage.transport,
    },
  );
  if (emitTimingEvent) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_TIMING',
      details: {
        'elapsedMs': sendStopwatch.elapsedMilliseconds,
        'outcome': 'success',
        'messageId': resolvedMessageId.substring(0, 8),
        'hasAttachments': attachments != null && attachments.isNotEmpty,
        'status': observedMessage.status,
        'via': observedMessage.transport,
        ...extraTimingDetails,
      },
    );
  }
  logChatOutgoing(
    messageId: resolvedMessageId,
    toPeerId: targetPeerId,
    status: observedMessage.status,
    text: text,
  );
  _recordSuccessfulSendReadinessProof(p2pService, observedMessage);
  // NET-REL-05 P3 (sticky transport): remember the LIVE transport that just
  // delivered so a repeat send to this peer can be weighted toward it (head-
  // start consumed in U-P2). Only acked LIVE deliveries qualify — 'inbox' is a
  // custody handoff, not a live transport, and `recordSuccessfulTransport`
  // ignores it anyway. This single success funnel covers connection reuse,
  // direct/local wins, and relay-live race wins; the inbox custody path and
  // unacked->inbox handoff intentionally do not record.
  if (observedMessage.status == 'delivered' &&
      observedMessage.transport != 'inbox') {
    p2pService.recordSuccessfulTransport(
      targetPeerId,
      observedMessage.transport ?? '',
    );
  }
  return (
    SendChatMessageResult.success,
    isOutgoingPrivateOneMoreLook
        ? persistedMessage?.copyWith(media: attachments ?? const [])
        : persistedMessage,
  );
}

SendChatMessageResult _resultForFailureReason(String? reason) {
  return switch (reason) {
    'peer_not_found' => SendChatMessageResult.peerNotFound,
    'dial_failed' => SendChatMessageResult.dialFailed,
    _ => SendChatMessageResult.sendFailed,
  };
}

Future<ConversationMessage> _persistOutgoingSendResult({
  required MessagePayload payload,
  required String targetPeerId,
  required String jsonString,
  required bool acknowledged,
  required String? createdAt,
  required String? editedAt,
  required String via,
  required _SendScopedInboxHedge inboxHedge,
  required bool requiresAckOrExpiryCustody,
}) async {
  if (acknowledged) {
    return payload.toConversationMessage(
      contactPeerId: targetPeerId,
      isIncoming: false,
      status: 'delivered',
      createdAt: createdAt,
      editedAt: editedAt,
      transport: via,
    );
  }

  // A written-only result force-starts or joins the same typed hedge. An
  // accepted or capacity-rejected initial outcome is authoritative. Only an
  // actual failed/throwing call receives the existing one fresh terminal retry.
  final wasAlreadyStarted = inboxHedge.hasStarted;
  if (!wasAlreadyStarted) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_UNACKED_INBOX_HANDOFF_BEGIN',
      details: {'via': via},
    );
  }
  var outcome = await inboxHedge.startOrJoin();
  if (outcome.status == InboxStoreStatus.failed) {
    if (wasAlreadyStarted) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_SEND_UNACKED_INBOX_HANDOFF_BEGIN',
        details: {'via': via},
      );
    }
    outcome = await inboxHedge.retryAfterFailure();
  }

  if (requiresAckOrExpiryCustody
      ? outcome.ackOrExpiryAccepted
      : outcome.accepted) {
    emitFlowEvent(
      layer: 'FL',
      event: wasAlreadyStarted
          ? 'CHAT_MSG_SEND_UNACKED_CONCURRENT_INBOX_CUSTODY'
          : 'CHAT_MSG_SEND_UNACKED_INBOX_HANDOFF_SUCCESS',
      details: {'via': via},
    );
    return payload
        .toConversationMessage(
          contactPeerId: targetPeerId,
          isIncoming: false,
          status: 'inboxed',
          createdAt: createdAt,
          editedAt: editedAt,
          transport: 'inbox',
          wireEnvelope: jsonString,
        )
        .copyWith(relayExpiresAt: outcome.expiresAtMs);
  }

  if (outcome.status == InboxStoreStatus.rejectedFull) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_INBOX_FULL_RETRYABLE',
      details: {'via': via},
    );
    return payload.toConversationMessage(
      contactPeerId: targetPeerId,
      isIncoming: false,
      status: 'sent',
      createdAt: createdAt,
      editedAt: editedAt,
      transport: 'inbox',
      wireEnvelope: jsonString,
    );
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'CHAT_MSG_SEND_UNACKED_INBOX_HANDOFF_FAILED',
    details: {'via': via, 'reason': outcome.errorCode ?? 'store_failed'},
  );

  emitFlowEvent(
    layer: 'FL',
    event: 'CHAT_MSG_SEND_UNACKED_PENDING_RETRY',
    details: {'via': via},
  );
  return payload.toConversationMessage(
    contactPeerId: targetPeerId,
    isIncoming: false,
    status: 'sent',
    createdAt: createdAt,
    editedAt: editedAt,
    transport: via,
    wireEnvelope: jsonString,
  );
}

/// 361: the shared blob-free fanout authoring tail for fresh text and text
/// EDIT. One logical inner event is encrypted independently per target, every
/// row commits before any network, and each committed row rides the incumbent
/// per-row protected-STORE owner independently — one outcome never cancels a
/// sibling.
Future<(SendChatMessageResult, ConversationMessage?)>
_authorDirectBlobFreeTextFanout({
  required DirectEventFanoutAuthoring directEventFanout,
  required DirectEventFanoutRouting routing,
  required P2PService p2pService,
  required MessageRepository messageRepo,
  required OutgoingDirectTextInboxCustodyRepository? directTextCustodyRepo,
  required OutgoingDirectTextMutationInboxCustodyRepository?
  directMutationCustodyRepo,
  required StoreInAckCustodyInboxDetailedFn? storeInAckCustodyInboxDetailed,
  required StoreInMediaExpiryBoundedInboxDetailedFn?
  storeInMediaExpiryBoundedInboxDetailed,
  required String action,
  required String targetPeerId,
  required String senderPeerId,
  required String senderUsername,
  required String sanitizedText,
  required String resolvedMessageId,
  required String resolvedTimestamp,
  required String? resolvedEventId,
  required String? resolvedEditedAt,
  required String? resolvedDedupKey,
  required String? quotedMessageId,
  required bool isForwarded,
  required List<Map<String, dynamic>>? media,
  required String? createdAt,
  required ConversationMessage? existingOutgoing,
  required void Function(String messageId)? onDirectTextCustodyStaged,
  required void Function({
    required String outcome,
    Map<String, dynamic> details,
  })
  emitSendTiming,
  required void Function({required String? transport, required String rung})
  recordMetrics,
}) async {
  final snapshot = routing.snapshot!;
  final isEdit = action == MessagePayload.actionEdit;
  final generationId = isEdit ? resolvedEventId! : resolvedMessageId;

  final payload = MessagePayload(
    id: resolvedMessageId,
    diagnosticTraceId: AppDiagnostics.instance.traceForOperation(
      'message:$resolvedMessageId',
    ),
    text: sanitizedText,
    senderPeerId: senderPeerId,
    senderUsername: senderUsername,
    timestamp: resolvedTimestamp,
    action: action,
    eventId: resolvedEventId,
    editedAt: resolvedEditedAt,
    quotedMessageId: quotedMessageId,
    media: media,
    dedupKey: resolvedDedupKey,
    isForwarded: isForwarded,
    privateMediaPolicy: const PrivateMediaPolicy.ordinary(),
  );

  // ONE authenticated logical inner event, encrypted independently per
  // target. The outer sender is the local installation's actual transport.
  final candidates = await directEventFanout.buildCandidates(
    snapshot: snapshot,
    innerPayloadJson: payload.toInnerJson(),
    buildEnvelope: ({required kem, required ciphertext, required nonce}) =>
        MessagePayload.buildEncryptedEnvelope(
          id: resolvedMessageId,
          senderPeerId: directEventFanout.senderTransportPeerId,
          senderUsername: senderUsername,
          kem: kem,
          ciphertext: ciphertext,
          nonce: nonce,
          eventId: resolvedEventId,
        ),
  );
  if (candidates == null) {
    emitSendTiming(outcome: 'fanout_encrypt_failed', details: const {});
    return (SendChatMessageResult.sendFailed, null);
  }

  final stagedRow = <String, Object?>{
    ...payload
        .toConversationMessage(
          contactPeerId: targetPeerId,
          isIncoming: false,
          status: 'sending',
          createdAt: isEdit
              ? (createdAt ?? existingOutgoing?.createdAt ?? resolvedTimestamp)
              : (createdAt ?? resolvedTimestamp),
          editedAt: resolvedEditedAt,
          wireEnvelope: candidates.first.wireEnvelope,
        )
        .toMap(),
    'direct_event_fanout_generation_id': generationId,
  };

  final DbDirectEventFanoutStageResult staged;
  if (isEdit) {
    final expected = existingOutgoing!;
    final expectedRow = <String, Object?>{
      ...expected.toMap(),
      if (expected.directEventFanoutGenerationId != null)
        'direct_event_fanout_generation_id':
            expected.directEventFanoutGenerationId,
    };
    staged = await directEventFanout.stageMutationFanout(
      expectedRow: expectedRow,
      stagedRow: stagedRow,
      kind: OutgoingOrdinaryAttemptKind.edit,
      eventId: resolvedEventId!,
      parentMessageId: resolvedMessageId,
      contactAccountPeerId: targetPeerId,
      senderTransportPeerId: directEventFanout.senderTransportPeerId,
      expectedSnapshot: snapshot,
      candidates: candidates,
    );
  } else {
    staged = await directEventFanout.stageTextFanout(
      stagedRow: stagedRow,
      messageId: resolvedMessageId,
      contactAccountPeerId: targetPeerId,
      senderTransportPeerId: directEventFanout.senderTransportPeerId,
      expectedSnapshot: snapshot,
      candidates: candidates,
    );
  }

  switch (staged.outcome) {
    case DirectEventFanoutStageOutcome.refused:
      emitSendTiming(outcome: 'fanout_stage_refused', details: const {});
      return (SendChatMessageResult.sendFailed, null);
    case DirectEventFanoutStageOutcome.terminal:
      // Zero survivors with the exact current generation: idempotent no-op.
      emitSendTiming(outcome: 'fanout_terminal_idempotent', details: const {});
      return (
        SendChatMessageResult.success,
        await messageRepo.getMessage(resolvedMessageId),
      );
    case DirectEventFanoutStageOutcome.survivorReplay:
    case DirectEventFanoutStageOutcome.applied:
      break;
  }
  if (staged.outcome == DirectEventFanoutStageOutcome.applied && !isEdit) {
    onDirectTextCustodyStaged?.call(resolvedMessageId);
  }

  // Network begins only after every row exists durably. Each row rides the
  // incumbent per-row owner; one acceptance or failure never cancels another
  // sibling. A missing strict store leaves rows to the global retrier.
  final rows = staged.rows ?? const <Map<String, Object?>>[];
  var completedRows = 0;
  for (final row in rows) {
    unawaited(
      p2pService
          .sendMessage(
            row['recipient_peer_id'] as String,
            row['wire_envelope'] as String,
          )
          .catchError((_) => false),
    );
    if (storeInAckCustodyInboxDetailed == null) continue;
    if (isEdit) {
      if (directMutationCustodyRepo == null) continue;
      final completed = await drainOwnedDirectMutationInboxCustodyOutboxEntry(
        entry: DirectReactionInboxCustodyOutboxEntry.fromMap(row),
        custodyRepository: directMutationCustodyRepo,
        storeInAckCustodyInboxDetailed: storeInAckCustodyInboxDetailed,
      );
      if (completed) completedRows++;
    } else {
      if (directTextCustodyRepo == null) continue;
      final attempt = await drainOwnedDirectInboxCustodyOutboxEntry(
        entry: DirectInboxCustodyOutboxEntry.fromMap(row),
        custodyRepository: directTextCustodyRepo,
        storeInAckCustodyInboxDetailed: storeInAckCustodyInboxDetailed,
        storeInMediaExpiryBoundedInboxDetailed:
            storeInMediaExpiryBoundedInboxDetailed,
      );
      if (attempt.completed) completedRows++;
    }
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'DIRECT_EVENT_FANOUT_AUTHORED',
    details: <String, Object?>{
      'id': shortenMessageId(resolvedMessageId),
      'kind': isEdit ? 'edit' : 'fresh_text',
      'targets': rows.length,
      'completed': completedRows,
      'replayedSurvivors':
          staged.outcome == DirectEventFanoutStageOutcome.survivorReplay,
    },
  );
  recordMetrics(transport: 'inbox', rung: 'inbox');
  emitSendTiming(outcome: 'success', details: const {});
  return (
    SendChatMessageResult.success,
    await messageRepo.getMessage(resolvedMessageId),
  );
}

/// 362: the blob-bearing fanout authoring tail for one strict-media initial.
/// The inner payload is ONE logical event encrypted independently per
/// persisted target; the complete per-target v108 batch commits atomically
/// (per-target manifest/expiry/envelope, canonical witness = FIRST target),
/// and each committed row rides the incumbent per-row strict-STORE owner
/// independently — one outcome never cancels a sibling.
/// 362: rebuilds the plural fanout context from persisted survivor rows.
///
/// Survivors are retry/settlement authority: every row must be a STORED
/// linked sibling of one logical contact equal to the send target, the
/// repository must own the fanout capability. No contact/roster resolver is
/// consulted: the complete persisted recipient/key rows are the obligation.
Future<DirectLinkedMediaFanoutContext?>
_deriveLinkedMediaFanoutContextFromSurvivors({
  required List<DirectMediaBlobCustodyRow> rows,
  required String targetPeerId,
  required MediaAttachmentRepository? mediaAttachmentRepo,
}) async {
  if (mediaAttachmentRepo is! OutgoingDirectLinkedMediaBlobFanoutRepository) {
    return null;
  }
  final fanoutRepository =
      mediaAttachmentRepo as OutgoingDirectLinkedMediaBlobFanoutRepository;
  if (!fanoutRepository.supportsDirectLinkedMediaBlobFanout) return null;
  if (rows.isEmpty ||
      rows.any(
        (row) =>
            !row.isLinkedFanoutRow ||
            row.contactAccountPeerId != targetPeerId ||
            row.direction != DirectMediaBlobCustodyDirection.outgoing ||
            row.state != DirectMediaBlobCustodyState.outgoingStored,
      )) {
    return null;
  }
  final targetRows = <String, List<DirectMediaBlobCustodyRow>>{};
  for (final row in rows) {
    targetRows
        .putIfAbsent(row.recipientPeerId!, () => <DirectMediaBlobCustodyRow>[])
        .add(row);
  }
  return DirectLinkedMediaFanoutContext.fromPersistedV114Survivors(
    contactAccountPeerId: targetPeerId,
    targetRows: targetRows,
  );
}

/// 366 private blob-bearing fanout authoring tail.
///
/// The one logical private payload is encrypted independently for every
/// persisted physical target. The incumbent private lifecycle lock performs
/// the completion compare-and-set once, then the explicit plural Barrier B
/// atomically binds the complete v114 set to N v108 siblings before egress.
Future<(SendChatMessageResult, ConversationMessage?)>
_authorDirectPrivateMediaFanout({
  required DirectPrivateMediaFanoutContext fanout,
  required P2PService p2pService,
  required MessageRepository messageRepo,
  required MediaAttachmentRepository mediaAttachmentRepo,
  required OutgoingDirectTextInboxCustodyRepository directTextCustodyRepo,
  required StoreInAckCustodyInboxDetailedFn? storeInAckCustodyInboxDetailed,
  required StoreInMediaExpiryBoundedInboxDetailedFn?
  storeInMediaExpiryBoundedInboxDetailed,
  required Bridge bridge,
  required String targetPeerId,
  required String senderPeerId,
  required String senderUsername,
  required MessagePayload payload,
  required ConversationMessage expectedParent,
  required MediaAttachment completedAttachment,
  required String resolvedMessageId,
  required void Function(String messageId)? onDirectTextCustodyStaged,
  required void Function({
    required String outcome,
    Map<String, dynamic> details,
  })
  emitSendTiming,
  required void Function({required String? transport, required String rung})
  recordMetrics,
}) async {
  (SendChatMessageResult, ConversationMessage?) refuse(String reason) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_PRIVATE_MEDIA_FANOUT_REFUSED',
      details: {'id': shortenMessageId(resolvedMessageId), 'reason': reason},
    );
    emitSendTiming(
      outcome: 'private_media_fanout_stage_refused',
      details: const {},
    );
    return (SendChatMessageResult.sendFailed, null);
  }

  final fanoutRepository =
      messageRepo is OutgoingDirectPrivateMediaFanoutInboxCustodyRepository
      ? messageRepo as OutgoingDirectPrivateMediaFanoutInboxCustodyRepository
      : null;
  final mutationRepository =
      mediaAttachmentRepo is OutgoingDirectPrivateMutationRepository
      ? mediaAttachmentRepo as OutgoingDirectPrivateMutationRepository
      : null;
  final outerSenderTransportPeerId = p2pService.currentState.peerId;
  final targets = fanout.targets;
  final targetPeerIds = targets.map((target) => target.peerId).toSet();
  final snapshot = fanout.snapshot;
  final exactAuthorityShape = switch (fanout.authority) {
    DirectPrivateMediaFanoutStageAuthority.currentRosterSnapshot =>
      snapshot != null &&
          snapshot.contactAccountPeerId == targetPeerId &&
          snapshot.targets.length == targets.length &&
          snapshot.targets.indexed.every((entry) {
            final (index, target) = entry;
            return target.peerId == targets[index].peerId &&
                target.mlKemPublicKey == targets[index].mlKemPublicKey;
          }),
    DirectPrivateMediaFanoutStageAuthority.persistedV114Survivors =>
      snapshot == null,
  };
  final commitment = completedAttachment.blobCustody;
  if (fanoutRepository == null ||
      !fanoutRepository.supportsOutgoingDirectPrivateMediaFanoutInboxCustody ||
      mutationRepository == null ||
      outerSenderTransportPeerId == null ||
      outerSenderTransportPeerId.trim().isEmpty ||
      fanout.contactAccountPeerId != targetPeerId ||
      !exactAuthorityShape ||
      targets.isEmpty ||
      targetPeerIds.length != targets.length ||
      fanout.targetRows.length != targets.length ||
      expectedParent.id != resolvedMessageId ||
      expectedParent.contactPeerId != targetPeerId ||
      expectedParent.senderPeerId != senderPeerId ||
      expectedParent.directMediaCustodyIntentId != null ||
      expectedParent.directEventFanoutGenerationId != resolvedMessageId ||
      !privateMediaInitialProducerMatrixAllows(
        policyVersion: expectedParent.privateMediaPolicy.version,
        mode: expectedParent.privateMediaMode,
        mime: completedAttachment.mime,
        mediaType: completedAttachment.mediaType,
      ) ||
      commitment == null ||
      !commitment.isValid ||
      commitment.contentHash != completedAttachment.contentHash) {
    return refuse('missing_private_fanout_authority');
  }

  final innerJson = payload.toInnerJson();
  final targetBindings = <DirectPrivateMediaFanoutTargetBinding>[];
  for (final target in targets) {
    final rows = fanout.targetRows[target.peerId];
    if (rows == null ||
        rows.length != 1 ||
        rows.single.messageId != resolvedMessageId ||
        rows.single.attachmentId != completedAttachment.id ||
        rows.single.recipientPeerId != target.peerId ||
        rows.single.contactAccountPeerId != targetPeerId ||
        rows.single.recipientMlKemPublicKey != target.mlKemPublicKey ||
        rows.single.direction != DirectMediaBlobCustodyDirection.outgoing ||
        rows.single.state != DirectMediaBlobCustodyState.outgoingStored ||
        !rows.single.isLinkedFanoutRow ||
        rows.single.contentHash != completedAttachment.contentHash ||
        rows.single.ciphertextSize != commitment.ciphertextSize ||
        rows.single.expiresAtMs == null) {
      return refuse('target_rows_incomplete');
    }
    final row = rows.single;
    final String manifestHash;
    try {
      manifestHash = computeDirectMediaBlobManifestHash(
        <DirectMediaBlobManifestProjection>[
          DirectMediaBlobManifestProjection(
            attachmentId: row.attachmentId,
            commitment: DirectMediaBlobCustodyCommitment(
              contentHash: row.contentHash,
              ciphertextSize: row.ciphertextSize,
              expiresAtMs: row.expiresAtMs!,
            ),
          ),
        ],
      );
    } on FormatException {
      return refuse('target_manifest_invalid');
    }
    final Map<String, dynamic> encrypted;
    try {
      encrypted = await callEncryptMessage(
        bridge: bridge,
        recipientMlKemPublicKey: target.mlKemPublicKey,
        plaintext: innerJson,
      );
    } catch (_) {
      emitSendTiming(
        outcome: 'private_media_fanout_encrypt_error',
        details: const {},
      );
      return (SendChatMessageResult.sendFailed, null);
    }
    if (encrypted['ok'] != true) {
      emitSendTiming(
        outcome: 'private_media_fanout_encrypt_failed',
        details: const {},
      );
      return (SendChatMessageResult.sendFailed, null);
    }
    targetBindings.add(
      DirectPrivateMediaFanoutTargetBinding(
        recipientPeerId: target.peerId,
        recipientMlKemPublicKey: target.mlKemPublicKey,
        wireEnvelope: MessagePayload.buildEncryptedEnvelope(
          id: resolvedMessageId,
          senderPeerId: outerSenderTransportPeerId,
          senderUsername: senderUsername,
          kem: encrypted['kem'] as String,
          ciphertext: encrypted['ciphertext'] as String,
          nonce: encrypted['nonce'] as String,
        ),
        wireMediaBlobManifestHash: manifestHash,
        wireMediaBlobExpiresAtMs: row.expiresAtMs!,
      ),
    );
  }

  late final String expectedPendingLocalPath;
  try {
    expectedPendingLocalPath =
        MediaFilePathConvention.relativePathForPendingUpload(
          messageId: resolvedMessageId,
          attachmentId: completedAttachment.id,
          mime: completedAttachment.mime,
        );
  } catch (_) {
    return refuse('invalid_pending_path');
  }
  final fingerprint = OutgoingDirectPrivateCompletionFingerprint.fromAttachment(
    completedAttachment,
    expectedPendingLocalPath: expectedPendingLocalPath,
  );
  if (!fingerprint.isStructurallyComplete) {
    return refuse('invalid_completion_fingerprint');
  }

  final coordinator =
      mutationRepository.outgoingDirectPrivateMutationCoordinator;
  final OutgoingDirectPrivateFanoutInboxCustodyResult staged;
  try {
    staged = await coordinator.lifecycleLock.synchronized(
      completedAttachment.id,
      () async {
        final owned = await coordinator.loadOwnedCompletionFingerprint(
          messageId: resolvedMessageId,
          attachmentId: completedAttachment.id,
          expectedPendingLocalPath: expectedPendingLocalPath,
        );
        final hasOwnedPendingCompletion = owned == fingerprint;
        if (!hasOwnedPendingCompletion) {
          final durable = await mediaAttachmentRepo.getAttachmentsForMessage(
            resolvedMessageId,
            owner: MediaOwnerLane.direct,
          );
          if (durable.length != 1 ||
              !fingerprint.matchesHydratedAttachment(durable.single)) {
            return const OutgoingDirectPrivateFanoutInboxCustodyResult.refused();
          }
        }
        return fanoutRepository
            .commitOutgoingDirectPrivateWireEnvelopeFanoutWithInboxCustody(
              messageId: resolvedMessageId,
              completedAttachment: completedAttachment,
              expectedPendingLocalPath: expectedPendingLocalPath,
              hasOwnedPendingCompletion: hasOwnedPendingCompletion,
              senderTransportPeerId: outerSenderTransportPeerId,
              contactAccountPeerId: targetPeerId,
              authority: fanout.authority,
              expectedSnapshot: snapshot,
              targetBindings: targetBindings,
            );
      },
    );
  } catch (_) {
    return refuse('private_barrier_b_error');
  }
  final stagedTargets = staged.custodies
      .map((entry) => entry.recipientPeerId)
      .toSet();
  if (!staged.authorizesTransport ||
      staged.custodies.length != targets.length ||
      stagedTargets.length != targets.length ||
      !stagedTargets.containsAll(targetPeerIds)) {
    return refuse('private_barrier_b_refused');
  }
  if (staged.outcome == OutgoingDirectPrivateEnvelopeHandoffOutcome.committed) {
    try {
      onDirectTextCustodyStaged?.call(resolvedMessageId);
    } catch (_) {
      // Durable authority already committed; an observer cannot revoke it.
    }
  }

  var completedRows = 0;
  for (final entry in staged.custodies) {
    unawaited(
      p2pService
          .sendMessage(entry.recipientPeerId, entry.wireEnvelope)
          .catchError((_) => false),
    );
    if (storeInAckCustodyInboxDetailed == null) continue;
    final attempt = await drainOwnedDirectInboxCustodyOutboxEntry(
      entry: entry,
      custodyRepository: directTextCustodyRepo,
      storeInAckCustodyInboxDetailed: storeInAckCustodyInboxDetailed,
      storeInMediaExpiryBoundedInboxDetailed:
          storeInMediaExpiryBoundedInboxDetailed,
    );
    if (attempt.completed) completedRows++;
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'DIRECT_PRIVATE_MEDIA_FANOUT_AUTHORED',
    details: <String, Object?>{
      'id': shortenMessageId(resolvedMessageId),
      'targets': staged.custodies.length,
      'completed': completedRows,
      'replayedSurvivors':
          staged.outcome ==
          OutgoingDirectPrivateEnvelopeHandoffOutcome.idempotent,
    },
  );
  recordMetrics(transport: 'inbox', rung: 'inbox');
  emitSendTiming(outcome: 'success', details: const {});
  return (
    SendChatMessageResult.success,
    await messageRepo.getMessage(resolvedMessageId),
  );
}

Future<(SendChatMessageResult, ConversationMessage?)>
_authorDirectLinkedMediaFanout({
  required DirectLinkedMediaFanoutContext fanout,
  required P2PService p2pService,
  required MessageRepository messageRepo,
  required MediaAttachmentRepository mediaAttachmentRepo,
  required OutgoingDirectTextInboxCustodyRepository? directTextCustodyRepo,
  required StoreInAckCustodyInboxDetailedFn? storeInAckCustodyInboxDetailed,
  required StoreInMediaExpiryBoundedInboxDetailedFn?
  storeInMediaExpiryBoundedInboxDetailed,
  required Bridge bridge,
  required String targetPeerId,
  required String senderPeerId,
  required String senderUsername,
  required MessagePayload payload,
  required ConversationMessage expectedParent,
  required List<MediaAttachment> normalizedAttachments,
  required String resolvedMessageId,
  required void Function(String messageId)? onDirectTextCustodyStaged,
  required void Function({
    required String outcome,
    Map<String, dynamic> details,
  })
  emitSendTiming,
  required void Function({required String? transport, required String rung})
  recordMetrics,
}) async {
  (SendChatMessageResult, ConversationMessage?) refuse(String reason) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_MEDIA_FANOUT_REFUSED',
      details: {'id': shortenMessageId(resolvedMessageId), 'reason': reason},
    );
    emitSendTiming(outcome: 'media_fanout_stage_refused', details: const {});
    return (SendChatMessageResult.sendFailed, null);
  }

  final fanoutRepository =
      mediaAttachmentRepo is OutgoingDirectLinkedMediaBlobFanoutRepository
      ? mediaAttachmentRepo as OutgoingDirectLinkedMediaBlobFanoutRepository
      : null;
  // 362: the encrypted inner payload is authored by the logical account, but
  // the outer envelope must name the node that actually authenticates the
  // transport. On a primary those peers are equal; on a linked secondary they
  // are deliberately distinct. Reusing [senderPeerId] here would make linked
  // media bypass the same physical->logical authority enforced for blob-free
  // events and would route delivery receipts to the dormant account mailbox.
  final outerSenderTransportPeerId = p2pService.currentState.peerId;
  final snapshot = fanout.snapshot;
  final targets = fanout.targets;
  final targetPeerIds = targets.map((target) => target.peerId).toSet();
  final exactAuthorityShape = switch (fanout.authority) {
    DirectMediaFanoutStageAuthority.currentRosterSnapshot =>
      snapshot != null &&
          snapshot.contactAccountPeerId == targetPeerId &&
          snapshot.targets.length == targets.length,
    DirectMediaFanoutStageAuthority.persistedV114Survivors => snapshot == null,
  };
  if (fanoutRepository == null ||
      !fanoutRepository.supportsDirectLinkedMediaBlobFanout ||
      outerSenderTransportPeerId == null ||
      outerSenderTransportPeerId.trim().isEmpty ||
      fanout.contactAccountPeerId != targetPeerId ||
      !exactAuthorityShape ||
      targets.isEmpty ||
      targetPeerIds.length != targets.length ||
      fanout.targetRows.length != targets.length ||
      expectedParent.id != resolvedMessageId ||
      expectedParent.contactPeerId != targetPeerId ||
      expectedParent.directMediaCustodyIntentId == null) {
    return refuse('missing_fanout_authority');
  }

  // The durable no-remint marker was committed WITH the v114 generation. A
  // caller snapshot that predates it threads the live row once, like the
  // blob-free TEXT fanout does; a live row without the marker fails closed.
  var markedParent = expectedParent;
  if (markedParent.directEventFanoutGenerationId != resolvedMessageId) {
    final ConversationMessage? liveParent;
    try {
      liveParent = await messageRepo.getMessage(resolvedMessageId);
    } catch (_) {
      return refuse('marker_read_error');
    }
    if (liveParent == null ||
        liveParent.directEventFanoutGenerationId != resolvedMessageId ||
        liveParent.contactPeerId != targetPeerId ||
        liveParent.directMediaCustodyIntentId !=
            expectedParent.directMediaCustodyIntentId) {
      return refuse('missing_generation_marker');
    }
    markedParent = liveParent;
  }

  // Per-target bindings ride the selected authority's exact target order.
  // Each target's manifest/expiry come from ONLY that target's persisted
  // STORED rows, and each envelope is encrypted with that row's exact key.
  final innerJson = payload.toInnerJson();
  final expectedAttachmentIds = normalizedAttachments
      .map((attachment) => attachment.id)
      .toSet();
  final targetBindings = <DirectMediaFanoutTargetBinding>[];
  for (final target in targets) {
    final rows = fanout.targetRows[target.peerId];
    if (rows == null ||
        rows.length != normalizedAttachments.length ||
        rows.any(
          (row) =>
              row.messageId != resolvedMessageId ||
              row.recipientPeerId != target.peerId ||
              row.contactAccountPeerId != targetPeerId ||
              // The persisted target key IS the encryption authority; it must
              // still be the snapshot target's exact key.
              row.recipientMlKemPublicKey != target.mlKemPublicKey ||
              row.state != DirectMediaBlobCustodyState.outgoingStored ||
              row.expiresAtMs == null ||
              !expectedAttachmentIds.contains(row.attachmentId),
        )) {
      return refuse('target_rows_incomplete');
    }
    final String manifestHash;
    final int expiresAtMs;
    try {
      final manifest = rows
          .map(
            (row) => DirectMediaBlobManifestProjection(
              attachmentId: row.attachmentId,
              commitment: DirectMediaBlobCustodyCommitment(
                contentHash: row.contentHash,
                ciphertextSize: row.ciphertextSize,
                expiresAtMs: row.expiresAtMs!,
              ),
            ),
          )
          .toList(growable: false);
      manifestHash = computeDirectMediaBlobManifestHash(manifest);
      expiresAtMs = earliestDirectMediaBlobExpiryMs(manifest);
    } on FormatException {
      return refuse('target_manifest_invalid');
    }
    final Map<String, dynamic> encryptResult;
    try {
      encryptResult = await callEncryptMessage(
        bridge: bridge,
        recipientMlKemPublicKey: rows.first.recipientMlKemPublicKey!,
        plaintext: innerJson,
      );
    } catch (_) {
      emitSendTiming(outcome: 'media_fanout_encrypt_error', details: const {});
      return (SendChatMessageResult.sendFailed, null);
    }
    if (encryptResult['ok'] != true) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_SEND_MEDIA_FANOUT_ENCRYPT_FAILED',
        details: {
          'id': shortenMessageId(resolvedMessageId),
          'errorCode': encryptResult['errorCode'],
        },
      );
      emitSendTiming(outcome: 'media_fanout_encrypt_failed', details: const {});
      return (SendChatMessageResult.sendFailed, null);
    }
    targetBindings.add(
      DirectMediaFanoutTargetBinding(
        recipientPeerId: target.peerId,
        recipientMlKemPublicKey: target.mlKemPublicKey,
        wireEnvelope: MessagePayload.buildEncryptedEnvelope(
          id: resolvedMessageId,
          senderPeerId: outerSenderTransportPeerId,
          senderUsername: senderUsername,
          kem: encryptResult['kem'] as String,
          ciphertext: encryptResult['ciphertext'] as String,
          nonce: encryptResult['nonce'] as String,
        ),
        wireMediaBlobManifestHash: manifestHash,
        wireMediaBlobExpiresAtMs: expiresAtMs,
      ),
    );
  }

  // The canonical staged row keeps the FIRST target's envelope and carries
  // the durable generation marker; runtime-only lifecycle fields preserve the
  // exact observed values so the staging CAS detects crossed work.
  final stagedAttempt = payload
      .toConversationMessage(
        contactPeerId: targetPeerId,
        isIncoming: false,
        status: 'sending',
        createdAt: markedParent.createdAt,
        wireEnvelope: targetBindings.first.wireEnvelope,
      )
      .copyWith(
        readAt: markedParent.readAt,
        privateMediaState: markedParent.privateMediaState,
        privateMediaReceivedAtMs: markedParent.privateMediaReceivedAtMs,
        privateMediaExpiresAtMs: markedParent.privateMediaExpiresAtMs,
        privateMediaRevealedAtMs: markedParent.privateMediaRevealedAtMs,
        privateMediaTerminalAtMs: markedParent.privateMediaTerminalAtMs,
        privateMediaClockHighWaterMs: markedParent.privateMediaClockHighWaterMs,
        directEventFanoutGenerationId: resolvedMessageId,
        media: normalizedAttachments,
      );

  DirectMediaFanoutInboxCustodyStageResult staged;
  try {
    staged = await fanoutRepository.stageOutgoingDirectMediaFanoutInboxCustody(
      expected: markedParent,
      staged: stagedAttempt,
      attachments: normalizedAttachments,
      senderTransportPeerId: outerSenderTransportPeerId,
      contactAccountPeerId: targetPeerId,
      authority: fanout.authority,
      expectedSnapshot: snapshot,
      targetBindings: targetBindings,
    );
  } catch (error) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_ATTEMPT_STAGE_ERROR',
      details: {
        'id': shortenMessageId(resolvedMessageId),
        'errorType': error.runtimeType.toString(),
      },
    );
    emitSendTiming(outcome: 'attempt_stage_error', details: const {});
    return (SendChatMessageResult.sendFailed, null);
  }
  if (!staged.authorizesTransport) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_SEND_ATTEMPT_STAGE_REFUSED',
      details: {
        'id': shortenMessageId(resolvedMessageId),
        'reason': staged.outcome.name,
      },
    );
    emitSendTiming(
      outcome: 'attempt_stage_refused',
      details: {'reason': staged.outcome.name},
    );
    return (SendChatMessageResult.sendFailed, null);
  }
  if (staged.outcome == OutgoingOrdinaryMutationOutcome.applied) {
    try {
      onDirectTextCustodyStaged?.call(resolvedMessageId);
    } catch (error) {
      // The atomic stage is already committed transport authority; an
      // observer failure can never revoke custody.
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_DIRECT_INBOX_CUSTODY_STAGE_OBSERVER_ERROR',
        details: {
          'id': shortenMessageId(resolvedMessageId),
          'errorType': error.runtimeType.toString(),
        },
      );
    }
  }

  // Network begins only after the whole batch exists durably. Each row rides
  // the incumbent per-row strict media-expiry-bounded owner; a missing store
  // or capability leaves rows to the global custody retrier.
  var completedRows = 0;
  for (final row in staged.custodyRows) {
    unawaited(
      p2pService
          .sendMessage(
            row['recipient_peer_id'] as String,
            row['wire_envelope'] as String,
          )
          .catchError((_) => false),
    );
    if (storeInAckCustodyInboxDetailed == null ||
        directTextCustodyRepo == null) {
      continue;
    }
    final attempt = await drainOwnedDirectInboxCustodyOutboxEntry(
      entry: DirectInboxCustodyOutboxEntry.fromMap(row),
      custodyRepository: directTextCustodyRepo,
      storeInAckCustodyInboxDetailed: storeInAckCustodyInboxDetailed,
      storeInMediaExpiryBoundedInboxDetailed:
          storeInMediaExpiryBoundedInboxDetailed,
    );
    if (attempt.completed) completedRows++;
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'DIRECT_MEDIA_FANOUT_AUTHORED',
    details: <String, Object?>{
      'id': shortenMessageId(resolvedMessageId),
      'targets': staged.custodyRows.length,
      'completed': completedRows,
      'replayedSurvivors':
          staged.outcome == OutgoingOrdinaryMutationOutcome.idempotent,
    },
  );
  recordMetrics(transport: 'inbox', rung: 'inbox');
  emitSendTiming(outcome: 'success', details: const {});
  return (
    SendChatMessageResult.success,
    staged.message ?? await messageRepo.getMessage(resolvedMessageId),
  );
}
