import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/database/helpers/media_attachments_db_helpers.dart'
    show IncomingDirectMediaCaptionEditOutcome;
import 'package:flutter_app/core/database/incoming_ordinary_text_mutation.dart';
import 'package:flutter_app/core/database/direct_media_blob_custody.dart';
import 'package:flutter_app/core/media/app_owned_media_delete_telemetry.dart';
import 'package:flutter_app/core/media/direct_media_blob_custody.dart';
import 'package:flutter_app/core/media/direct_private_media_path_guard.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart'
    show kMediaDownloadStatusDone;
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_file_path_convention.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/utils/text_sanitizer.dart';
import 'package:flutter_app/core/utils/chat_console_logger.dart';
import 'package:flutter_app/features/conversation/application/send_delivery_receipt_use_case.dart'
    show deliveryReceiptMintDecision, kConfirmatoryDirectLanReceiptEnabled;
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/contacts/application/direct_transport_authority.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/incoming_direct_media_blob_custody_result.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/message_payload.dart';
import 'package:flutter_app/features/conversation/domain/repositories/direct_private_media_lifecycle_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:path/path.dart' as p;

/// Result of handling an incoming chat message.
enum HandleChatMessageResult {
  /// Valid chat message received and stored.
  chatMessage,

  /// Not a chat_message type — ignore.
  notChatMessage,

  /// V2 chat message could not be decrypted because required local key
  /// material is not currently available.
  missingMlKemSecret,

  /// V2 chat message decryption failed cryptographically (Go-returned
  /// failure). Terminal for this attempt; the staged entry must be kept.
  decryptionFailed,

  /// V2 chat message decryption hit a transient infrastructure failure
  /// (bridge timeout or thrown bridge exception). Safe to retry later;
  /// the message content was never evaluated.
  decryptionDeferred,

  /// Sender is not a known contact.
  unknownSender,

  /// Duplicate message ID already stored.
  duplicate,

  /// Edit references an original message that is not stored locally.
  editMissingOriginal,

  /// Sender identifiers do not agree or the edit does not belong to the
  /// original author.
  unauthorized,

  /// Edit was ignored because it is stale, duplicate, or targets a deleted row.
  ignoredEdit,

  /// A strict blob commitment was partial, crossed, or could not be staged by
  /// the required all-or-zero receiver authority.
  strictMediaCustodyRefused,

  /// Plan 354: a durable same-author private terminal parent already owns this
  /// target, or one won between the atomic stage and publication. The event is
  /// durably settled and its single initial receipt was emitted, but NOTHING
  /// was published: no attachment/key write, marker stage or promotion, stream
  /// event, notification, or listener-level message-display retry. Callers
  /// must not route this through the generic duplicate branch.
  durablySuperseded,

  /// 361: an AUTHENTICATED linked transport carried a modality the restricted
  /// linked role does not support (ordinary media, Protected/View-Once/
  /// disappearing, unsupported private). Terminal: rejected/quarantined with
  /// zero v111/private lifecycle/apply/receipt/publication/notification.
  linkedModalityRefused,
}

typedef StageDirectMessageNotificationDisplayCustody =
    Future<void> Function(ConversationMessage message);
typedef PromoteDirectMessageNotificationDisplayCustody =
    Future<void> Function(ConversationMessage message);
typedef SendIncomingMessageDeliveryReceipt =
    Future<void> Function(String messageId);
typedef SendIncomingMessageMutationDeliveryReceipt =
    Future<void> Function(String messageId, {required String mutationEventId});

/// Parses an incoming P2P ChatMessage for chat_message type,
/// validates the sender, checks for duplicates, and persists.
///
/// Returns (result, ConversationMessage?, ContactModel?) —
/// message is non-null on chatMessage, updatedContact is non-null when
/// the sender's username changed since last stored.
Future<(HandleChatMessageResult, ConversationMessage?, ContactModel?)>
handleIncomingChatMessage({
  required ChatMessage message,
  required MessageRepository messageRepo,
  required ContactRepository contactRepo,
  Bridge? bridge,
  String? ownMlKemSecretKey,
  // Prior ML-KEM secrets (newest first) tried in order when the primary
  // secret fails CRYPTOGRAPHICALLY — same-device recovery of traffic
  // encrypted to a pre-restore key (P0-B). Never consulted on transient
  // failures.
  List<String>? fallbackMlKemSecretKeys,
  // 147: when non-null, the inbox-drain decrypt-prefetch pass already decrypted
  // this message's v2 envelope (concurrently, ahead of the serial commit loop)
  // and supplies the inner plaintext JSON here. The handler then SKIPS its own
  // bridge decrypt + ML-KEM fallback ring and uses this verbatim. When null (the
  // live default + every gate-off path) the handler decrypts itself, byte-
  // identically to before. A prefetch that failed/omitted an entry leaves this
  // null, so the entry simply falls back to the in-handler decrypt (never
  // dropped, never mis-disposed).
  String? predecryptedText,
  MediaAttachmentRepository? mediaAttachmentRepo,
  // Used by the duplicate-replay media repair to invalidate staged
  // artifacts left behind by a previous key/nonce (112 Phase 1).
  MediaFileManager? mediaFileManager,
  String? transport,
  // 115 P2: delivery-receipt hook + arrival-origin marker. The hook fires
  // AFTER a durable persist (and on duplicate receives, closing the
  // lost-receipt repair loop) — but ONLY for relay-inbox arrivals per the
  // shared origin contract (shouldMintDeliveryReceipt): 'direct:'/'lan:'
  // staged replays are confirmed by their own acks.
  SendIncomingMessageDeliveryReceipt? sendDeliveryReceipt,
  SendIncomingMessageMutationDeliveryReceipt? sendMutationDeliveryReceipt,
  String? stagedEntryId,
  // 132 Phase 1: when true (the live default), a confirmatory receipt is minted
  // for direct/LAN/non-inbox durable arrivals too. Test seam — production passes
  // the const default.
  bool confirmatoryDirectLanEnabled = kConfirmatoryDirectLanReceiptEnabled,
  StageDirectMessageNotificationDisplayCustody? stageNotificationDisplayCustody,
  PromoteDirectMessageNotificationDisplayCustody?
  promoteNotificationDisplayCustody,
  // 361: when present, the shared physical->logical reverse authority.
  // `null` keeps the incumbent transport==logical equality byte-identically.
  DirectTransportAuthorityResolver? transportAuthority,
}) async {
  Future<void> maybeSendDeliveryReceipt(
    String messageId, {
    String? mutationEventId,
  }) async {
    if (sendDeliveryReceipt == null && sendMutationDeliveryReceipt == null) {
      return;
    }
    final decision = deliveryReceiptMintDecision(
      stagedEntryId: stagedEntryId,
      transport: transport,
      confirmatoryDirectLanEnabled: confirmatoryDirectLanEnabled,
    );
    if (!decision.shouldMint) {
      // 132 Phase 0: name the dead-end behind a stuck pending clock — a
      // genuinely-delivered direct/LAN (or non-inbox) message gets NO receipt,
      // so the sender's row never converges to 'delivered'.
      emitFlowEvent(
        layer: 'FL',
        event: 'DELIVERY_RECEIPT_MINT_SKIPPED',
        details: {
          'reason': decision.skipReason!.name,
          'transport': transport,
          'id': messageId.length > 8 ? messageId.substring(0, 8) : messageId,
        },
      );
      return;
    }
    // 146: detach the per-message receipt SEND from the replay/critical path.
    // The message is already durably persisted (saveMessage, above) and the
    // receipt is custody confirmation TO THE SENDER — the receiving user gains
    // nothing by waiting for it. Awaiting it here serialized N relay round-trips
    // into the inbox-drain loop (p2p_service_impl `_replayStagedInboxEntries`),
    // blocking the screen reload on every notif-tap. Fire-and-forget: the mint
    // DECISION above stays synchronous and per-message; only the network send is
    // deferred (never dropped — the 132 confirmatory receipt still goes out, and
    // it is idempotent on the sender, so reordering is harmless). The
    // `.catchError` keeps the now-unawaited future from raising an unhandled
    // async error and preserves the DELIVERY_RECEIPT_HOOK_ERROR breadcrumb.
    // `Future.sync` wraps the call so a hook that throws SYNCHRONOUSLY (before
    // returning a Future) is funnelled into the same `.catchError` — matching
    // the old `try { await ... } catch` which caught both sync and async throws.
    unawaited(
      Future.sync(
        () => mutationEventId != null && sendMutationDeliveryReceipt != null
            ? sendMutationDeliveryReceipt(
                messageId,
                mutationEventId: mutationEventId,
              )
            : sendDeliveryReceipt?.call(messageId) ?? Future<void>.value(),
      ).catchError((Object e) {
        emitFlowEvent(
          layer: 'FL',
          event: 'DELIVERY_RECEIPT_HOOK_ERROR',
          details: {
            'id': messageId.length > 8 ? messageId.substring(0, 8) : messageId,
            'error': e.toString(),
          },
        );
      }),
    );
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'CHAT_MSG_RECEIVE_START',
    details: {
      'from': message.from.length > 10
          ? message.from.substring(0, 10)
          : message.from,
    },
  );

  // Log raw wire envelope
  logChatWireEnvelope(
    direction: 'IN',
    messageId: '',
    wireJson: message.content,
  );

  // 1. Try v2 encrypted envelope first, then fall back to v1 plaintext
  MessagePayload? payload;

  final v2Envelope = MessagePayload.parseEncryptedEnvelope(message.content);
  final envelopeSenderPeerId = v2Envelope?['senderPeerId'] as String?;
  if (v2Envelope != null) {
    if (predecryptedText != null) {
      // 147: the inbox-drain prefetch already decrypted this envelope (running
      // the SAME primary + ML-KEM ring as below, via predecryptIncomingChatEnvelope)
      // concurrently ahead of the serial commit loop. Use the supplied inner
      // plaintext verbatim and skip the bridge round-trip entirely.
      payload = MessagePayload.fromDecryptedJson(predecryptedText);
    } else {
      // v2 encrypted message — decrypt in-handler (the live default and the
      // fallback for any entry the prefetch omitted/failed).
      final decryptOutcome = await _decryptV2ChatEnvelope(
        v2Envelope: v2Envelope,
        bridge: bridge,
        ownMlKemSecretKey: ownMlKemSecretKey,
        fallbackMlKemSecretKeys: fallbackMlKemSecretKeys,
      );
      switch (decryptOutcome.status) {
        case _V2DecryptStatus.missingKey:
          emitFlowEvent(
            layer: 'FL',
            event: 'CHAT_MSG_RECEIVE_V2_NO_KEY',
            details: {},
          );
          return (HandleChatMessageResult.missingMlKemSecret, null, null);
        case _V2DecryptStatus.deferred:
          // BRIDGE_TIMEOUT is synthesized on the Dart side (bridge.dart) when
          // the native call never answered — the ciphertext was never
          // evaluated, so the failure is transient, not cryptographic.
          emitFlowEvent(
            layer: 'FL',
            event: 'CHAT_MSG_RECEIVE_DECRYPT_DEFERRED',
            details: {'errorCode': decryptOutcome.errorCode},
          );
          return (HandleChatMessageResult.decryptionDeferred, null, null);
        case _V2DecryptStatus.failed:
          emitFlowEvent(
            layer: 'FL',
            event: 'CHAT_MSG_RECEIVE_DECRYPT_FAILED',
            details: {'errorCode': decryptOutcome.errorCode},
          );
          return (HandleChatMessageResult.decryptionFailed, null, null);
        case _V2DecryptStatus.error:
          emitFlowEvent(
            layer: 'FL',
            event: 'CHAT_MSG_RECEIVE_DECRYPT_ERROR',
            details: {'error': decryptOutcome.errorDetail},
          );
          return (HandleChatMessageResult.decryptionDeferred, null, null);
        case _V2DecryptStatus.ok:
          if (decryptOutcome.ringFallbackUsed) {
            // Cryptographic failure with the primary secret recovered via a
            // pre-restore key in the ring (P0-B).
            emitFlowEvent(
              layer: 'FL',
              event: 'MLKEM_RING_FALLBACK_USED',
              details: {},
            );
          }
          payload = MessagePayload.fromDecryptedJson(decryptOutcome.plaintext!);
      }
    }
  } else {
    // v1 plaintext envelope
    payload = MessagePayload.fromJson(message.content);
  }

  if (payload == null) {
    emitFlowEvent(layer: 'FL', event: 'CHAT_MSG_RECEIVE_NOT_CHAT', details: {});
    return (HandleChatMessageResult.notChatMessage, null, null);
  }

  // TC-342-08: the cleartext v2 target id and optional mutation event id must
  // each agree with their authenticated inner authority before any side effect.
  // Fresh sends use only the authored message id. Edits additionally carry a
  // distinct event id so relay dedupe cannot confuse their ciphertext with the
  // initial send; legacy edits without that additive field remain readable.
  final outerEnvelopeId = v2Envelope?['id'];
  final outerEventId = v2Envelope?['eventId'];
  final payloadEventId = payload.eventId;
  final hasMutationEventId = outerEventId != null || payloadEventId != null;
  final mutationEventIdValid =
      !hasMutationEventId ||
      (payload.isEdit &&
          outerEventId is String &&
          outerEventId.trim().isNotEmpty &&
          outerEventId == payloadEventId);
  if (v2Envelope != null &&
      (outerEnvelopeId != payload.id || !mutationEventIdValid)) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_RECEIVE_ID_MISMATCH',
      details: {
        'reason': outerEnvelopeId != payload.id ? 'target_id' : 'event_id',
        'envelopeId': outerEnvelopeId is String
            ? (outerEnvelopeId.length > 8
                  ? outerEnvelopeId.substring(0, 8)
                  : outerEnvelopeId)
            : '<missing>',
        'payloadId': payload.id.length > 8
            ? payload.id.substring(0, 8)
            : payload.id,
      },
    );
    return (HandleChatMessageResult.unauthorized, null, null);
  }

  // Sanitize incoming text and username to strip bidi control characters
  final incomingPrivateMediaPolicy = payload.privateMediaPolicy;
  payload = MessagePayload(
    id: payload.id,
    text: incomingPrivateMediaPolicy.requiresRedaction
        ? ''
        : sanitizeMessageText(payload.text),
    senderPeerId: payload.senderPeerId,
    senderUsername: sanitizeUsername(payload.senderUsername),
    timestamp: payload.timestamp,
    action: payload.action,
    eventId: payload.eventId,
    editedAt: payload.editedAt,
    quotedMessageId: payload.quotedMessageId,
    media: payload.media,
    dedupKey: payload.dedupKey, // F8 tier-2: must survive the sanitize rebuild
    isForwarded: payload.isForwarded,
    privateMediaPolicy: incomingPrivateMediaPolicy,
  );
  final strictMediaProjection = _parseStrictIncomingMediaProjection(payload);
  // 359: a malformed strict NON-edit keeps its immediate refusal exactly where
  // it is. Only an invalid EDIT defers that decision, so the authenticated
  // private-EDIT disposition below can discard it terminally instead of
  // leaving a retryable strict-custody refusal redriving forever.
  // 2a. Identity: the outer envelope sender must equal the authenticated
  // PHYSICAL transport, and the decrypted payload sender must equal the
  // resolved LOGICAL contact. Without a resolver the incumbent
  // transport==logical equality applies byte-identically.
  DirectTransportAuthorityResolution? transportResolution;
  bool senderMismatch;
  if (transportAuthority == null) {
    senderMismatch =
        message.from != payload.senderPeerId ||
        (v2Envelope != null && envelopeSenderPeerId != payload.senderPeerId);
  } else {
    transportResolution = await transportAuthority
        .resolveDirectTransportAuthority(message.from);
    senderMismatch =
        (v2Envelope != null && envelopeSenderPeerId != message.from) ||
        !transportResolution.authorized ||
        transportResolution.contactAccountPeerId != payload.senderPeerId;
  }
  final isLinkedTransportOrigin =
      transportResolution?.kind == DirectTransportAuthorityKind.linked;

  if (strictMediaProjection.selected &&
      !strictMediaProjection.isValid &&
      !payload.isEdit) {
    // 361: an authenticated linked transport's unsupported modality is
    // TERMINAL, never a retryable strict-custody refusal.
    if (!senderMismatch && isLinkedTransportOrigin) {
      return (HandleChatMessageResult.linkedModalityRefused, null, null);
    }
    return (HandleChatMessageResult.strictMediaCustodyRefused, null, null);
  }

  if (senderMismatch) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_RECEIVE_SENDER_MISMATCH',
      details: {
        'streamFrom': message.from.length > 10
            ? message.from.substring(0, 10)
            : message.from,
        'envelopeFrom': envelopeSenderPeerId == null
            ? '<missing>'
            : (envelopeSenderPeerId.length > 10
                  ? envelopeSenderPeerId.substring(0, 10)
                  : envelopeSenderPeerId),
        'payloadFrom': payload.senderPeerId.length > 10
            ? payload.senderPeerId.substring(0, 10)
            : payload.senderPeerId,
      },
    );
    return (HandleChatMessageResult.unauthorized, null, null);
  }

  // 2. Check sender is a known contact
  final contact = await contactRepo.getContact(payload.senderPeerId);
  if (contact == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_RECEIVE_UNKNOWN_SENDER',
      details: {
        'senderPeerId': payload.senderPeerId.length > 10
            ? payload.senderPeerId.substring(0, 10)
            : payload.senderPeerId,
      },
    );
    return (HandleChatMessageResult.unknownSender, null, null);
  }

  // 361: the restricted linked role supported blob-free ordinary text events
  // only. 362: an authenticated linked transport now carries STRICT direct
  // media (ordinary and the supported private/disappearing shapes) through
  // the same exact-custody stage paths as a legacy origin — the raw physical
  // transport stays the authenticated sender/receipt route while the
  // decrypted logical account becomes the canonical contact. Everything
  // outside the strict projection (legacy media transport, crossed private
  // shapes without strict custody) remains terminally rejected before any
  // v111, private-lifecycle, apply, receipt, publication or notification
  // work exists.
  if (isLinkedTransportOrigin &&
      !strictMediaProjection.selected &&
      ((payload.media != null && payload.media!.isNotEmpty) ||
          payload.privateMediaPolicy.version != 0 ||
          payload.privateMediaPolicy.mode != PrivateMediaMode.ordinary)) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_RECEIVE_LINKED_MODALITY_REFUSED',
      details: {'id': shortenMessageId(payload.id)},
    );
    return (HandleChatMessageResult.linkedModalityRefused, null, null);
  }

  // 359 (D-234-01): private caption/text EDIT is an unsupported product
  // action, so it is discarded through the EXISTING terminal `ignoredEdit`
  // outcome instead of gaining custody. Sender and contact are already
  // authenticated above; one durable target read then decides.
  //
  // Ordering is deliberate: a crossed parent author stays `unauthorized`, an
  // EDIT whose normalized wire policy OR same-author durable target requires
  // redaction (including a persisted unknown-version `unsupported`
  // checkpoint) is terminally ignored BEFORE the Plan 353 caption, duplicate,
  // missing-original and generic edit branches, and any remaining
  // non-redacted invalid EDIT then keeps the strict refusal it has today.
  // D-234-07's unsupported PERSISTENCE applies to received media items, not to
  // an unsupported mutation that would grant edit semantics.
  //
  // The ignored mutation writes no placeholder, parent, attachment, key or
  // marker, publishes nothing and emits no application mutation receipt. Live
  // transport confirmation and the recovered-inbox `ignoredEdit -> rejected`
  // disposition terminally drain it without a new enum or outcome.
  if (payload.isEdit) {
    final durableEditTarget = await messageRepo.getMessage(payload.id);
    if (durableEditTarget != null &&
        (durableEditTarget.senderPeerId != payload.senderPeerId ||
            durableEditTarget.contactPeerId != payload.senderPeerId)) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_RECEIVE_EDIT_UNAUTHORIZED',
        details: {'id': shortenMessageId(payload.id)},
      );
      return (HandleChatMessageResult.unauthorized, null, null);
    }
    if (payload.privateMediaPolicy.requiresRedaction ||
        (durableEditTarget?.privateMediaPolicy.requiresRedaction ?? false)) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_RECEIVE_PRIVATE_EDIT_UNSUPPORTED',
        details: {'id': shortenMessageId(payload.id)},
      );
      return (HandleChatMessageResult.ignoredEdit, null, null);
    }
    if (strictMediaProjection.selected && !strictMediaProjection.isValid) {
      return (HandleChatMessageResult.strictMediaCustodyRefused, null, null);
    }
  }

  final isOrdinaryDirectText =
      !strictMediaProjection.selected &&
      (payload.media == null || payload.media!.isEmpty) &&
      payload.privateMediaPolicy.version == 0 &&
      payload.privateMediaPolicy.mode == PrivateMediaMode.ordinary;
  final ordinaryTextApplyRepository =
      messageRepo is IncomingOrdinaryTextApplyRepository
      ? messageRepo as IncomingOrdinaryTextApplyRepository
      : null;
  if (isOrdinaryDirectText && ordinaryTextApplyRepository == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_RECEIVE_ORDINARY_TEXT_AUTHORITY_UNAVAILABLE',
      details: {
        'id': payload.id.length > 8 ? payload.id.substring(0, 8) : payload.id,
      },
    );
    return (HandleChatMessageResult.unauthorized, null, null);
  }

  // 353: an exact event-bearing proof-less media caption EDIT is routed BEFORE
  // the generic missing/stale/deleted branches. Its authority is the persisted
  // strict generation, so it must never reach the family-agnostic placeholder
  // save or the non-atomic parent/attachment writes below.
  final isDirectMediaCaptionEditCandidate =
      payload.isEdit &&
      !strictMediaProjection.selected &&
      (payload.media?.isNotEmpty ?? false) &&
      payload.privateMediaPolicy.version == 0 &&
      payload.privateMediaPolicy.mode == PrivateMediaMode.ordinary &&
      v2Envelope != null &&
      outerEventId is String &&
      outerEventId.trim().isNotEmpty &&
      outerEventId == payloadEventId;
  if (isDirectMediaCaptionEditCandidate) {
    final captionEditRepo =
        mediaAttachmentRepo is IncomingDirectMediaCaptionEditApplyRepository
        ? mediaAttachmentRepo as IncomingDirectMediaCaptionEditApplyRepository
        : null;
    if (captionEditRepo == null ||
        !captionEditRepo.supportsIncomingDirectMediaCaptionEditApply) {
      // Fail closed and retryable: the exact staged envelope stays the owner
      // until a capable build can validate it.
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_RECEIVE_MEDIA_CAPTION_EDIT_AUTHORITY_UNAVAILABLE',
        details: {'id': shortenMessageId(payload.id)},
      );
      return (HandleChatMessageResult.editMissingOriginal, null, null);
    }
    // Dart cannot retain the nullable payload's promotion across a closure.
    final captionEditMessageId = payload.id;
    final descriptors = payload.media!
        .map(
          (mediaJson) => MediaAttachment.fromJson(mediaJson).copyWith(
            messageId: captionEditMessageId,
            ownerLane: MediaOwnerLane.direct,
          ),
        )
        .toList(growable: false);
    final candidate = payload.toConversationMessage(
      contactPeerId: payload.senderPeerId,
      isIncoming: true,
      status: 'delivered',
      editedAt: payload.editedAt ?? payload.timestamp,
      transport: transport,
    );
    IncomingDirectMediaCaptionEditApplyResult applied;
    try {
      applied = await captionEditRepo.applyIncomingDirectMediaCaptionEdit(
        incoming: candidate,
        attachments: descriptors,
      );
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_RECEIVE_MEDIA_CAPTION_EDIT_APPLY_ERROR',
        details: {
          'id': shortenMessageId(payload.id),
          'errorType': error.runtimeType.toString(),
        },
      );
      return (HandleChatMessageResult.editMissingOriginal, null, null);
    }
    switch (applied.outcome) {
      case IncomingDirectMediaCaptionEditOutcome.missingOriginal:
        // Zero writes: no parent, no attachment, no marker, no receipt.
        emitFlowEvent(
          layer: 'FL',
          event: 'CHAT_MSG_RECEIVE_EDIT_MISSING_ORIGINAL',
          details: {'id': shortenMessageId(payload.id)},
        );
        return (HandleChatMessageResult.editMissingOriginal, null, null);
      case IncomingDirectMediaCaptionEditOutcome.refused:
        emitFlowEvent(
          layer: 'FL',
          event: 'CHAT_MSG_RECEIVE_MEDIA_CAPTION_EDIT_REFUSED',
          details: {'id': shortenMessageId(payload.id)},
        );
        return (HandleChatMessageResult.strictMediaCustodyRefused, null, null);
      case IncomingDirectMediaCaptionEditOutcome.legacyParent:
        // A live pre-353 all-null/no-v111 parent keeps its exact existing
        // generic media-edit apply and its existing event-aware receipt.
        break;
      case IncomingDirectMediaCaptionEditOutcome.applied:
        final durable = applied.message;
        if (durable != null) {
          await stageNotificationDisplayCustody?.call(durable);
        }
        await maybeSendDeliveryReceipt(
          payload.id,
          mutationEventId: payload.eventId,
        );
        return (HandleChatMessageResult.chatMessage, durable, null);
      case IncomingDirectMediaCaptionEditOutcome.durableReplay:
      case IncomingDirectMediaCaptionEditOutcome.superseded:
        await maybeSendDeliveryReceipt(
          payload.id,
          mutationEventId: payload.eventId,
        );
        return (HandleChatMessageResult.ignoredEdit, null, null);
    }
  }

  // 3. Check for duplicate / same-ID edit update
  final existingMessage = await messageRepo.getMessage(payload.id);
  final shouldMaterializeDeferredEdit =
      existingMessage != null &&
      !payload.isEdit &&
      _isHiddenIncomingEditPlaceholder(existingMessage);
  // 355: a selected strict-private replay whose durable parent is already
  // terminal is routed AROUND generic duplicate handling. The dedicated
  // private DB owner is the only authority that may compare the surviving
  // custody and mint the one zero-effect receipt; the generic branch would
  // instead promote display and return `duplicate`, telling the listener to
  // retry global display work for media the user can no longer see.
  final strictPrivateTerminalReplay =
      existingMessage != null &&
      !payload.isEdit &&
      strictMediaProjection.selected &&
      strictMediaProjection.isPrivate &&
      _isDurableStrictPrivateTerminalParent(existingMessage);
  // 358: an ACTIVE disappearing replay is owned by the same transactional
  // private stage. The generic duplicate branch promotes display and returns
  // `duplicate`; it can compare neither the durable receiver clock nor the
  // hydrated key material this modality depends on, and a due replay must be
  // able to expire instead of re-presenting the card.
  final strictDisappearingReplay =
      existingMessage != null &&
      !payload.isEdit &&
      strictMediaProjection.selected &&
      strictMediaProjection.isPrivate &&
      payload.privateMediaPolicy.mode == PrivateMediaMode.disappearing;
  final strictPrivateOwnedReplay =
      strictPrivateTerminalReplay || strictDisappearingReplay;
  final shouldPreserveDeletedPlaceholder =
      existingMessage != null &&
      !payload.isEdit &&
      !strictPrivateOwnedReplay &&
      _isIncomingDeletedPlaceholder(existingMessage);
  if (existingMessage != null &&
      !payload.isEdit &&
      !isOrdinaryDirectText &&
      !shouldMaterializeDeferredEdit &&
      !shouldPreserveDeletedPlaceholder &&
      !strictPrivateOwnedReplay) {
    if (payload.text != existingMessage.text) {
      final idPrefix = payload.id.length > 8
          ? payload.id.substring(0, 8)
          : payload.id;
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_RECEIVE_DUPLICATE_CONTENT_MISMATCH',
        details: {
          'id': idPrefix,
          'incomingTextLength': payload.text.length,
          'existingTextLength': existingMessage.text.length,
          'existingHasEditedAt': existingMessage.editedAt != null,
        },
      );
    }
    if (strictMediaProjection.selected) {
      final exact = await _isExactStrictIncomingDuplicate(
        messageId: payload.id,
        projection: strictMediaProjection,
        mediaAttachmentRepo: mediaAttachmentRepo,
      );
      if (!exact) {
        return (HandleChatMessageResult.strictMediaCustodyRefused, null, null);
      }
    } else {
      await _repairDuplicateReplayMedia(
        payload: payload,
        existingParent: existingMessage,
        mediaAttachmentRepo: mediaAttachmentRepo,
        mediaFileManager: mediaFileManager,
      );
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_RECEIVE_DUPLICATE',
      details: {'id': payload.id.substring(0, 8)},
    );
    // FDC-S6 instrument point 5 (net-new double-delivery counter): a same-id
    // re-delivery dropped by the messageId dedup is the only place the LAN
    // double-delivery rate can be measured. Record the transport leg of BOTH
    // the KEPT copy (the already-stored existingMessage) and the DROPPED copy
    // (this incoming message's `transport`), so the soak can tally collisions
    // keyed by the (first-leg, second-leg) pair — e.g. wifi+direct (WS + libp2p
    // both won), or under FDC-12 relay+direct / inbox+direct. Labels are short,
    // non-sensitive bucket strings (never a peerId/multiaddr), so they survive
    // flow_event_emitter redaction. Observation-only; no behaviour change.
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_DOUBLE_DELIVERY',
      details: {
        'id': payload.id.length > 8 ? payload.id.substring(0, 8) : payload.id,
        'kept': existingMessage.transport,
        'dropped': transport,
      },
    );
    // Duplicate receive of an already-durable message: re-mint the receipt
    // (the sender may have missed the first one — D-5 repair loop).
    await maybeSendDeliveryReceipt(payload.id);
    final markerAuthorityMatchesCanonical =
        existingMessage.id == payload.id &&
        existingMessage.contactPeerId == payload.senderPeerId &&
        existingMessage.senderPeerId == payload.senderPeerId &&
        existingMessage.timestamp == payload.timestamp &&
        existingMessage.isIncoming;
    if (markerAuthorityMatchesCanonical) {
      // Duplicate replay is the recovery leg for a crash after save (or media
      // repair) but before ready promotion. Divergent authority never promotes
      // an event-id collision.
      await promoteNotificationDisplayCustody?.call(existingMessage);
    }
    return (HandleChatMessageResult.duplicate, null, null);
  }
  if (existingMessage == null && payload.isEdit && !isOrdinaryDirectText) {
    final stagedEdit = _buildHiddenIncomingEditPlaceholder(
      payload: payload,
      transport: transport,
    );
    await messageRepo.saveMessage(stagedEdit);
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_RECEIVE_EDIT_MISSING_ORIGINAL',
      details: {'id': payload.id.substring(0, 8)},
    );
    return (HandleChatMessageResult.editMissingOriginal, null, null);
  }

  if (payload.isEdit && existingMessage != null) {
    if (existingMessage.senderPeerId != payload.senderPeerId) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_RECEIVE_EDIT_UNAUTHORIZED',
        details: {'id': payload.id.substring(0, 8)},
      );
      return (HandleChatMessageResult.unauthorized, null, null);
    }
    if (!isOrdinaryDirectText && existingMessage.isDeleted) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_RECEIVE_EDIT_IGNORED_DELETED',
        details: {'id': payload.id.substring(0, 8)},
      );
      return (HandleChatMessageResult.ignoredEdit, null, null);
    }
    final incomingEditedAt = payload.editedAt ?? payload.timestamp;
    final currentEditedAt = existingMessage.editedAt;
    if (!isOrdinaryDirectText &&
        currentEditedAt != null &&
        !_isIncomingEditNewer(
          incomingEditedAt: incomingEditedAt,
          currentEditedAt: currentEditedAt,
        )) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_RECEIVE_EDIT_IGNORED_STALE',
        details: {'id': payload.id.substring(0, 8)},
      );
      return (HandleChatMessageResult.ignoredEdit, null, null);
    }
  }

  // 3b. Content-level duplicate (F8): a divergent-id re-delivery of the same
  // logical message (e.g. a second delivery channel, or a re-minted id carrying
  // the original wire timestamp) would otherwise persist a second row under a
  // new id — the 1:1 twin of the group double-card. Only a brand-new, non-edit
  // arrival can be a content duplicate; same-id edits, hidden-edit
  // materialization and deleted-placeholder merges are intentional transitions
  // (existingMessage != null) and must not be swallowed.
  //
  // Tier-2 (F8, wire-stamped `dedupKey`) takes PRECEDENCE: a logical delivery
  // key (including one Forward action token) survives a re-mint of BOTH id and
  // timestamp, which the
  // timestamp-exact tier-1 below cannot catch. A keyed-but-UNMATCHED arrival is
  // authoritatively new and does NOT fall back to tier-1. Tier-1
  // (timestamp-exact `existsByContent`) remains the legacy / keyless-sender
  // fallback, byte-identical to before.
  if (existingMessage == null && !payload.isEdit) {
    final dedupKey = payload.dedupKey;
    if (dedupKey != null && dedupKey.isNotEmpty) {
      final isDedupKeyDuplicate = await messageRepo.existsByDedupKey(
        payload.senderPeerId,
        payload.senderPeerId,
        dedupKey,
      );
      if (isDedupKeyDuplicate) {
        emitFlowEvent(
          layer: 'FL',
          event: 'CHAT_MSG_RECEIVE_DUPLICATE_DEDUP_KEY',
          details: {
            'id': payload.id.length > 8
                ? payload.id.substring(0, 8)
                : payload.id,
          },
        );
        // Same logical content already durable under a different id+timestamp
        // (a forward) — re-mint the receipt for the forward's fresh id so the
        // sender's forward row is acknowledged, then drop the duplicate card.
        await maybeSendDeliveryReceipt(payload.id);
        return (HandleChatMessageResult.duplicate, null, null);
      }
    } else {
      final isContentDuplicate = await messageRepo.existsByContent(
        payload.senderPeerId,
        payload.senderPeerId,
        payload.text,
        payload.timestamp,
      );
      if (isContentDuplicate) {
        emitFlowEvent(
          layer: 'FL',
          event: 'CHAT_MSG_RECEIVE_DUPLICATE_CONTENT',
          details: {
            'id': payload.id.length > 8
                ? payload.id.substring(0, 8)
                : payload.id,
          },
        );
        // The content is already durable under a different id — re-mint the
        // receipt so the sender's new-id send is still acknowledged, then drop.
        await maybeSendDeliveryReceipt(payload.id);
        return (HandleChatMessageResult.duplicate, null, null);
      }
    }
  }

  // 5. Persist message
  var resultAfterSave = shouldPreserveDeletedPlaceholder
      ? HandleChatMessageResult.duplicate
      : HandleChatMessageResult.chatMessage;
  final candidateMessage = payload.isEdit && existingMessage == null
      ? _buildHiddenIncomingEditPlaceholder(
          payload: payload,
          transport: transport,
        )
      : shouldMaterializeDeferredEdit
      ? _materializeIncomingOriginalFromHiddenEdit(
          hiddenEditMessage: existingMessage,
          payload: payload,
          transport: transport,
        )
      : shouldPreserveDeletedPlaceholder
      ? _mergeIncomingOriginalIntoDeletedPlaceholder(
          deletedMessage: existingMessage,
          payload: payload,
          transport: transport,
        )
      : payload.isEdit && existingMessage != null
      ? existingMessage.copyWith(
          senderPeerId: payload.senderPeerId,
          text: payload.text,
          status: 'delivered',
          editedAt:
              payload.editedAt ?? DateTime.now().toUtc().toIso8601String(),
          quotedMessageId:
              payload.quotedMessageId ?? existingMessage.quotedMessageId,
          transport: transport ?? existingMessage.transport,
          dedupKey: payload.dedupKey,
          isForwarded: payload.isForwarded,
          privateMediaPolicy: payload.privateMediaPolicy.requiresRedaction
              ? payload.privateMediaPolicy
              : existingMessage.privateMediaPolicy,
          privateMediaState: payload.privateMediaPolicy.requiresRedaction
              ? payload.privateMediaPolicy.initialState
              : existingMessage.privateMediaState,
        )
      : payload.toConversationMessage(
          contactPeerId: payload.senderPeerId,
          isIncoming: true,
          status: 'delivered',
          editedAt: payload.editedAt,
          transport: transport,
        );
  var conversationMessage = _seedIncomingPrivateMediaLifecycle(
    candidateMessage,
    // A terminal replay must qualify against the DB with the FRESH wire
    // candidate. Seeding the durable terminal checkpoint into it would make
    // the staging shape invalid and the dedicated terminal branch
    // unreachable, which is exactly how Plan 354 lost this route.
    existingMessage: strictPrivateTerminalReplay ? null : existingMessage,
  );
  final parsedAttachments = <MediaAttachment>[];
  // The strict-private lane promotes its own display marker inside the single
  // exclusive lifecycle decision below, so the later generic site must not
  // promote it a second time outside that authority.
  var privateReadyPromoted = false;
  if (strictMediaProjection.selected) {
    final incomingMessageRepo =
        messageRepo is IncomingDirectMessagePublicationRepository
        ? messageRepo as IncomingDirectMessagePublicationRepository
        : null;
    final incomingMediaRepo =
        mediaAttachmentRepo is IncomingDirectMediaBlobCustodyRepository
        ? mediaAttachmentRepo as IncomingDirectMediaBlobCustodyRepository
        : null;
    final incomingPrivateMediaRepo =
        mediaAttachmentRepo is IncomingDirectPrivateMediaBlobCustodyRepository
        ? mediaAttachmentRepo as IncomingDirectPrivateMediaBlobCustodyRepository
        : null;
    // 358: a strict private initial additionally requires the incumbent
    // message-lifecycle owner and the media cleanup runtime that carries the
    // repository-wide exclusive lease. Without both, the receiver-local clock
    // cannot be evaluated under the same authority that publishes it, so the
    // attempt fails closed with zero secure-key, DB or display effects.
    final privateLifecycleMessageRepo =
        messageRepo is DirectPrivateMediaLifecycleRepository
        ? messageRepo as DirectPrivateMediaLifecycleRepository
        : null;
    final privateCleanupRuntime =
        mediaAttachmentRepo is DirectPrivateMediaCleanupRuntime
        ? mediaAttachmentRepo as DirectPrivateMediaCleanupRuntime
        : null;
    if (resultAfterSave != HandleChatMessageResult.chatMessage ||
        incomingMessageRepo == null ||
        incomingMediaRepo == null ||
        !incomingMediaRepo.supportsIncomingDirectMediaBlobCustody ||
        (strictMediaProjection.isPrivate &&
            (incomingPrivateMediaRepo
                        ?.supportsIncomingDirectPrivateMediaBlobCustody !=
                    true ||
                privateLifecycleMessageRepo == null ||
                privateCleanupRuntime == null))) {
      // A selected strict private attempt fails closed when its capability is
      // absent; it must never fall back to the legacy split saves.
      return (HandleChatMessageResult.strictMediaCustodyRefused, null, null);
    }
    final now = DateTime.now().toUtc().toIso8601String();
    // Capture the promoted payload identity before entering closures. Dart
    // cannot retain promotion of the nullable parse result across callbacks.
    final strictMessageId = payload.id;
    final strictSenderPeerId = payload.senderPeerId;
    final strictAttachments = strictMediaProjection.attachments
        .map(
          (attachment) => attachment.copyWith(
            messageId: strictMessageId,
            ownerLane: MediaOwnerLane.direct,
          ),
        )
        .toList(growable: false);
    final custodyRows = strictAttachments
        .map((attachment) {
          final commitment = attachment.blobCustody!;
          return DirectMediaBlobCustodyRow(
            attachmentId: attachment.id,
            messageId: strictMessageId,
            direction: DirectMediaBlobCustodyDirection.incoming,
            state: DirectMediaBlobCustodyState.incomingCommitted,
            inboxCustodyIncarnationId: null,
            recipientPeerId: null,
            // 362: a LINKED origin persists the logical contact as the
            // durable discriminator on newly authored incoming v114 rows;
            // legacy origins keep the incumbent NULL marker byte-identically.
            contactAccountPeerId: isLinkedTransportOrigin
                ? strictSenderPeerId
                : null,
            ciphertextRelativePath: null,
            custodyKind: commitment.kind,
            custodyContract: commitment.contract,
            contentHash: commitment.contentHash,
            ciphertextSize: commitment.ciphertextSize,
            transportMime: commitment.transportMime,
            expiresAtMs: commitment.expiresAtMs,
            custodyRelayPeerId: null,
            lastAttemptAt: null,
            nextAttemptAt: null,
            createdAt: now,
            updatedAt: now,
          );
        })
        .toList(growable: false);
    // 355/358: ONE repository-wide exclusive lease spans the hydrated replay
    // barrier, the atomic stage, the durable re-read, the receiver-deadline
    // decision, the guarded thumbnail, the display-marker stage, the
    // repository publication and the ready promotion. Nested repository
    // acquisitions inside it are reentrant. Network, contact metadata and
    // receipt transport deliberately stay outside.
    final IncomingDirectMediaBlobCustodyStageResult staged;
    _StrictPrivateReceiveDecision? privateDecision;
    if (strictMediaProjection.isPrivate) {
      final strictRawMedia = payload.media;
      final wireIdentity = candidateMessage;
      final custodyReader =
          mediaAttachmentRepo is DirectMediaBlobCustodyRepository
          ? mediaAttachmentRepo as DirectMediaBlobCustodyRepository
          : null;
      final leased = await _underPrivateLifecycleAuthority(
        mediaAttachmentRepo,
        () async {
          // The hydrated replay barrier. An ACTIVE durable parent must prove
          // the same immutable wire identity AND the same hydrated raw key
          // material before this attempt may write anything at all — a
          // canonicalized candidate must never be able to hide that drift.
          final durableBefore = await messageRepo.getMessage(strictMessageId);
          var stageMessage = conversationMessage;
          var stageCustody = custodyRows.single;
          var stageAttachment = strictAttachments.single;
          MediaAttachment? durableReplayAttachment;
          if (durableBefore != null &&
              !_isDurableStrictPrivateTerminalParent(durableBefore)) {
            if (!_matchesActiveStrictPrivateReplayIdentity(
              durable: durableBefore,
              wire: wireIdentity,
            )) {
              return (
                staged:
                    const IncomingDirectMediaBlobCustodyStageResult.refused(),
                decision: null,
              );
            }
            final durableAttachments = await mediaAttachmentRepo!
                .getAttachmentsForMessage(
                  strictMessageId,
                  owner: MediaOwnerLane.direct,
                );
            if (durableAttachments.length != 1 ||
                !_sameHydratedStrictPrivateAttachment(
                  durableAttachments.single,
                  strictAttachments.single,
                )) {
              return (
                staged:
                    const IncomingDirectMediaBlobCustodyStageResult.refused(),
                decision: null,
              );
            }
            durableReplayAttachment = durableAttachments.single;
            // The attachment's local creation stamp is the FIRST delivery's,
            // exactly like the parent's.
            stageAttachment = strictAttachments.single.copyWith(
              createdAt: durableReplayAttachment.createdAt,
            );
            // The local arrival stamp and the local read stamp belong to the
            // FIRST durable delivery. A replay re-mints neither, so the exact
            // idempotent comparison inside the stage is against the row this
            // receiver actually committed.
            stageMessage = conversationMessage.copyWith(
              createdAt: durableBefore.createdAt,
              readAt: durableBefore.readAt,
            );
            // Same reasoning for the v111 obligation: an exact replay adopts
            // the durable row's own audit stamps instead of minting new ones,
            // and a survivor whose public commitment or state disagrees is
            // crossed authority that fails closed with no receipt.
            final durableCustody = await custodyReader
                ?.loadIncomingDirectMediaBlobCustodyForAttachment(
                  strictAttachments.single.id,
                );
            if (durableCustody == null ||
                durableCustody.state !=
                    DirectMediaBlobCustodyState.incomingCommitted ||
                !_sameStrictPrivateCustodyCommitment(
                  durableCustody,
                  custodyRows.single,
                )) {
              return (
                staged:
                    const IncomingDirectMediaBlobCustodyStageResult.refused(),
                decision: null,
              );
            }
            stageCustody = durableCustody;
          }
          // An exact ACTIVE replay whose durable attachment has already left
          // the fresh `pending` projection (the user downloaded it) has
          // nothing left to stage: its parent identity, hydrated attachment
          // identity and v111 commitment were all just proved under this same
          // lease. Re-running the insert-shaped stage would refuse the very
          // row it already owns, so adopt the durable projection instead.
          final adoptsDurableReplay =
              durableReplayAttachment != null &&
              (durableReplayAttachment.downloadStatus != 'pending' ||
                  durableReplayAttachment.localPath != null);
          final result = adoptsDurableReplay
              ? IncomingDirectMediaBlobCustodyStageResult(
                  outcome:
                      IncomingDirectMediaBlobCustodyStageOutcome.idempotent,
                  attachments: <MediaAttachment>[durableReplayAttachment],
                )
              : await incomingPrivateMediaRepo!
                    .stageIncomingDirectPrivateMediaBlobCustody(
                      message: stageMessage,
                      attachment: stageAttachment,
                      custodyRow: stageCustody,
                      authenticatedTransportPeerId: isLinkedTransportOrigin
                          ? message.from
                          : null,
                    );
          if (!result.outcome.isDurable) {
            return (staged: result, decision: null);
          }
          final durableParent = await messageRepo.getMessage(strictMessageId);
          if (durableParent == null) {
            // Without a durable parent there is no author or policy authority
            // for this event, so nothing is published AND no receipt is owed.
            return (
              staged: result,
              decision: _StrictPrivateReceiveDecision.parentRemoved,
            );
          }
          if (durableParent.hiddenAt != null ||
              durableParent.deletedAt != null ||
              durableParent.privateMediaState.isTerminal) {
            // No display marker was staged yet on this path, so suppression is
            // simply never staging one; the exact terminal owner retires any
            // marker an earlier receive left behind.
            return (
              staged: result,
              decision: _StrictPrivateReceiveDecision.terminal,
            );
          }
          // 358: the due-ONLY receiver-deadline decision. Before the deadline
          // the general stream-emitting clock advance is deliberately NOT
          // called, so the first `available` event a listener can observe is
          // post-marker. At or after it, the existing lifecycle advance runs
          // exactly once, its transaction retires the exact display marker,
          // and every presentation effect is suppressed.
          final deadlineMs = durableParent.privateMediaExpiresAtMs;
          if (durableParent.privateMediaMode == PrivateMediaMode.disappearing &&
              deadlineMs != null) {
            final sampledNowMs = DateTime.now().millisecondsSinceEpoch;
            final highWaterMs = durableParent.privateMediaClockHighWaterMs ?? 0;
            final effectiveNowMs = sampledNowMs > highWaterMs
                ? sampledNowMs
                : highWaterMs;
            if (effectiveNowMs >= deadlineMs) {
              await privateLifecycleMessageRepo!.advancePrivateMediaClock(
                strictMessageId,
                nowMs: effectiveNowMs,
              );
              final reloaded = await messageRepo.getMessage(strictMessageId);
              if (reloaded != null && reloaded.privateMediaState.isTerminal) {
                return (
                  staged: result,
                  decision: _StrictPrivateReceiveDecision.terminal,
                );
              }
              // The durable state contradicts the decision this lease just
              // made. Fail closed and retryable rather than presenting media
              // behind an unevaluated deadline.
              return (
                staged: result,
                decision: _StrictPrivateReceiveDecision.parentRemoved,
              );
            }
          }
          // The Protected inline thumbnail is a best-effort guarded sibling.
          // It never becomes authority, never blocks the receipt, and existing
          // private cleanup still owns its removal.
          if (mediaFileManager != null && (strictRawMedia?.length ?? 0) == 1) {
            await _persistIncomingProtectedPhotoThumbnail(
              rawMediaJson: strictRawMedia!.single,
              attachment: strictAttachments.single,
              parent: conversationMessage,
              mediaFileManager: mediaFileManager,
            );
          }
          await stageNotificationDisplayCustody?.call(conversationMessage);
          // Publish only the stage result's hydrated durable attachment; the
          // caller/wire snapshot is never republished behind it.
          final publication = await incomingMessageRepo
              .publishIncomingDirectMediaMessage(
                message: conversationMessage,
                attachments: result.attachments.isEmpty
                    ? strictAttachments
                    : result.attachments,
              );
          if (publication ==
              StrictIncomingMediaPublicationDisposition.durablySuperseded) {
            return (
              staged: result,
              decision: _StrictPrivateReceiveDecision.terminal,
            );
          }
          // Ready promotion belongs to the same decision: every attachment
          // effect for this lane is already durable, and leaving it to the
          // later generic site would let a terminal owner win in between.
          await promoteNotificationDisplayCustody?.call(conversationMessage);
          return (
            staged: result,
            decision: _StrictPrivateReceiveDecision.published,
          );
        },
      );
      staged = leased.staged;
      privateDecision = leased.decision;
    } else {
      staged = await incomingMediaRepo.stageIncomingDirectMediaBlobCustody(
        message: conversationMessage,
        attachments: strictAttachments,
        custodyRows: custodyRows,
        authenticatedTransportPeerId: isLinkedTransportOrigin
            ? message.from
            : null,
      );
    }
    if (staged.outcome ==
        IncomingDirectMediaBlobCustodyStageOutcome.durablySuperseded) {
      // 354: a durable same-author private terminal parent already won. This
      // is a dedicated zero-effect disposition: no attachment/key write, no
      // marker stage or promotion, no publication, stream or notification, and
      // never the generic duplicate/display-retry branch. The initial receipt
      // is still owed and is emitted only after that durable winner was
      // re-read inside the staging transaction.
      await maybeSendDeliveryReceipt(payload.id);
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_RECEIVE_STRICT_PRIVATE_DURABLY_SUPERSEDED',
        details: {
          'id': payload.id.length > 8 ? payload.id.substring(0, 8) : payload.id,
        },
      );
      return (HandleChatMessageResult.durablySuperseded, null, null);
    }
    if (staged.outcome ==
        IncomingDirectMediaBlobCustodyStageOutcome.supersededByDeletion) {
      // The author's deletion is durable precedence, not a refusal. Publish no
      // media, marker, or notification — but still settle the event with the
      // one initial receipt the sender is waiting for.
      await maybeSendDeliveryReceipt(payload.id);
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_RECEIVE_STRICT_MEDIA_SUPERSEDED_BY_DELETION',
        details: {
          'id': payload.id.length > 8 ? payload.id.substring(0, 8) : payload.id,
        },
      );
      // A private supersession is never generic `duplicate`: that result asks
      // the listener to retry global display work for media the durable owner
      // already retired.
      return (
        strictMediaProjection.isPrivate
            ? HandleChatMessageResult.durablySuperseded
            : HandleChatMessageResult.duplicate,
        null,
        null,
      );
    }
    if (!staged.outcome.isDurable) {
      return (HandleChatMessageResult.strictMediaCustodyRefused, null, null);
    }
    parsedAttachments.addAll(strictAttachments);
    if (strictMediaProjection.isPrivate) {
      // The one exclusive decision above already ran under the lease.
      switch (privateDecision!) {
        case _StrictPrivateReceiveDecision.parentRemoved:
          emitFlowEvent(
            layer: 'FL',
            event: 'CHAT_MSG_RECEIVE_STRICT_PRIVATE_PARENT_REMOVED',
            details: {
              'id': payload.id.length > 8
                  ? payload.id.substring(0, 8)
                  : payload.id,
            },
          );
          return (
            HandleChatMessageResult.strictMediaCustodyRefused,
            null,
            null,
          );
        case _StrictPrivateReceiveDecision.terminal:
          await maybeSendDeliveryReceipt(payload.id);
          emitFlowEvent(
            layer: 'FL',
            event: 'CHAT_MSG_RECEIVE_STRICT_PRIVATE_TERMINAL_AFTER_STAGE',
            details: {
              'id': payload.id.length > 8
                  ? payload.id.substring(0, 8)
                  : payload.id,
            },
          );
          return (HandleChatMessageResult.durablySuperseded, null, null);
        case _StrictPrivateReceiveDecision.published:
          privateReadyPromoted = true;
      }
      await maybeSendDeliveryReceipt(payload.id);
    } else {
      // The complete parent/attachment/v111 transaction is already durable.
      // Every observable side effect starts only after that boundary.
      await stageNotificationDisplayCustody?.call(conversationMessage);
      final published = await incomingMessageRepo
          .publishIncomingDirectMediaMessage(
            message: conversationMessage,
            attachments: strictAttachments,
          );
      if (published ==
          StrictIncomingMediaPublicationDisposition.durablySuperseded) {
        await maybeSendDeliveryReceipt(payload.id);
        emitFlowEvent(
          layer: 'FL',
          event: 'CHAT_MSG_RECEIVE_STRICT_MEDIA_SUPERSEDED_BY_DELETION',
          details: {
            'id': payload.id.length > 8
                ? payload.id.substring(0, 8)
                : payload.id,
          },
        );
        return (HandleChatMessageResult.duplicate, null, null);
      }
      await maybeSendDeliveryReceipt(payload.id);
    }
  } else {
    if (isOrdinaryDirectText) {
      IncomingOrdinaryTextApplyResult applied;
      // 361: a linked origin re-authorizes inside the durable apply itself.
      final linkedApplyRepository =
          isLinkedTransportOrigin &&
              messageRepo is LinkedTransportIncomingApplyRepository
          ? messageRepo as LinkedTransportIncomingApplyRepository
          : null;
      if (isLinkedTransportOrigin &&
          (linkedApplyRepository == null ||
              !linkedApplyRepository.supportsLinkedTransportIncomingApply)) {
        return (HandleChatMessageResult.unauthorized, null, null);
      }
      try {
        applied = linkedApplyRepository != null
            ? await linkedApplyRepository
                  .applyIncomingOrdinaryTextMutationWithTransportAuthority(
                    incoming: conversationMessage,
                    kind: payload.isEdit
                        ? IncomingOrdinaryTextMutationKind.edit
                        : IncomingOrdinaryTextMutationKind.initial,
                    authenticatedTransportPeerId: message.from,
                  )
            : await ordinaryTextApplyRepository!
                  .applyIncomingOrdinaryTextMutation(
                    incoming: conversationMessage,
                    kind: payload.isEdit
                        ? IncomingOrdinaryTextMutationKind.edit
                        : IncomingOrdinaryTextMutationKind.initial,
                  );
      } catch (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'CHAT_MSG_RECEIVE_ORDINARY_TEXT_APPLY_ERROR',
          details: {'errorType': error.runtimeType.toString()},
        );
        return (HandleChatMessageResult.unauthorized, null, null);
      }
      if (!applied.isDurable || applied.message == null) {
        return (HandleChatMessageResult.unauthorized, null, null);
      }
      conversationMessage = applied.message!;
      final durableReplay = !applied.changed;
      if (payload.isEdit &&
          applied.outcome == IncomingOrdinaryTextMutationOutcome.inserted) {
        await maybeSendDeliveryReceipt(
          payload.id,
          mutationEventId: payload.eventId,
        );
        emitFlowEvent(
          layer: 'FL',
          event: 'CHAT_MSG_RECEIVE_EDIT_MISSING_ORIGINAL',
          details: {'id': payload.id.substring(0, 8)},
        );
        return (HandleChatMessageResult.editMissingOriginal, null, null);
      }
      if (payload.isEdit && durableReplay) {
        await maybeSendDeliveryReceipt(
          payload.id,
          mutationEventId: payload.eventId,
        );
        return (HandleChatMessageResult.ignoredEdit, null, null);
      }
      if (!payload.isEdit && durableReplay) {
        final durableMessage = applied.message!;
        if (payload.text != durableMessage.text) {
          emitFlowEvent(
            layer: 'FL',
            event: 'CHAT_MSG_RECEIVE_DUPLICATE_CONTENT_MISMATCH',
            details: {
              'id': payload.id.length > 8
                  ? payload.id.substring(0, 8)
                  : payload.id,
              'incomingTextLength': payload.text.length,
              'existingTextLength': durableMessage.text.length,
              'existingHasEditedAt': durableMessage.editedAt != null,
            },
          );
        }
        emitFlowEvent(
          layer: 'FL',
          event: 'CHAT_MSG_RECEIVE_DUPLICATE',
          details: {
            'id': payload.id.length > 8
                ? payload.id.substring(0, 8)
                : payload.id,
          },
        );
        emitFlowEvent(
          layer: 'FL',
          event: 'CHAT_MSG_DOUBLE_DELIVERY',
          details: {
            'id': payload.id.length > 8
                ? payload.id.substring(0, 8)
                : payload.id,
            'kept': durableMessage.transport,
            'dropped': transport,
          },
        );
        await maybeSendDeliveryReceipt(payload.id);
        final markerAuthorityMatchesCanonical =
            durableMessage.id == payload.id &&
            durableMessage.contactPeerId == payload.senderPeerId &&
            durableMessage.senderPeerId == payload.senderPeerId &&
            durableMessage.timestamp == payload.timestamp &&
            durableMessage.isIncoming;
        if (markerAuthorityMatchesCanonical) {
          await promoteNotificationDisplayCustody?.call(durableMessage);
        }
        return (HandleChatMessageResult.duplicate, null, null);
      }
    }
    if (resultAfterSave == HandleChatMessageResult.chatMessage) {
      // Ordinary text has already crossed its atomic parent transaction. Media
      // and legacy lanes keep their existing marker-before-save ordering.
      await stageNotificationDisplayCustody?.call(conversationMessage);
    }
    if (!isOrdinaryDirectText) {
      await messageRepo.saveMessage(conversationMessage);
    }
    // 115 P2: the message is durably persisted — confirm custody to the
    // sender (relay-drain arrivals only, per the origin contract).
    await maybeSendDeliveryReceipt(
      payload.id,
      mutationEventId: payload.isEdit ? payload.eventId : null,
    );
  }
  if (shouldMaterializeDeferredEdit) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_RECEIVE_EDIT_MATERIALIZED',
      details: {'id': payload.id.substring(0, 8)},
    );
  }
  if (shouldPreserveDeletedPlaceholder) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_RECEIVE_ORIGINAL_IGNORED_AFTER_DELETE',
      details: {'id': payload.id.substring(0, 8)},
    );
  }

  // 6. Persist legacy media attachment metadata and collect parsed attachments.
  if (!strictMediaProjection.selected &&
      !shouldPreserveDeletedPlaceholder &&
      mediaAttachmentRepo != null &&
      payload.media != null) {
    for (final mediaJson in payload.media!) {
      // The hydrated message feeds the live UI before any DB reload, and the
      // private-media eligibility engine fails closed (wrongOwner) on a
      // lane-less attachment — stamp the lane the save below persists.
      final attachment = MediaAttachment.fromJson(
        mediaJson,
      ).copyWith(messageId: payload.id, ownerLane: MediaOwnerLane.direct);
      final saved = await _saveIncomingDirectAttachment(
        repository: mediaAttachmentRepo,
        attachment: attachment,
        parent: conversationMessage,
        rawMediaJson: mediaJson,
        mediaFileManager: mediaFileManager,
      );
      if (saved) parsedAttachments.add(attachment);
    }
  }

  // 4. Contact metadata is independent from message custody, but must not be
  // observable before a strict message's complete atomic stage.
  ContactModel? updatedContact;
  if (contact.username != payload.senderUsername) {
    updatedContact = contact.copyWith(username: payload.senderUsername);
    await contactRepo.addContact(updatedContact);
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_CONTACT_NAME_UPDATED',
      details: {
        'peerId': contact.peerId.length > 10
            ? contact.peerId.substring(0, 10)
            : contact.peerId,
        'oldName': contact.username,
        'newName': payload.senderUsername,
      },
    );
  }
  if (resultAfterSave == HandleChatMessageResult.chatMessage &&
      !privateReadyPromoted) {
    // Attachment metadata is part of the canonical notification snapshot.
    // Ready must not become visible until every attachment save/repair above
    // has committed, otherwise a crash can terminalize a generic card and lose
    // the later media projection.
    await promoteNotificationDisplayCustody?.call(conversationMessage);
  }

  // 7. Hydrate media on the returned message so downstream consumers
  // (notably ChatMessageListener.maybeShowNotification) can derive the
  // notification body from media metadata without a separate DB query.
  // This mirrors the send-path pattern at send_chat_message_use_case.dart:695.
  final hydratedMessage = parsedAttachments.isNotEmpty
      ? conversationMessage.copyWith(media: parsedAttachments)
      : conversationMessage;

  final storedTextPreview = buildTextPreview(conversationMessage.text);

  emitFlowEvent(
    layer: 'FL',
    event: 'CHAT_MSG_RECEIVE_STORED',
    details: {
      'id': payload.id.substring(0, 8),
      'from': payload.senderPeerId.length > 10
          ? payload.senderPeerId.substring(0, 10)
          : payload.senderPeerId,
      // FDC-S6: unlike the per-leg MSG_RECEIVED_TRANSPORT signal, this event
      // fires only after the authoritative logical message is stored. Carry
      // the kept transport so inbox replay (which bypasses that per-leg signal)
      // remains visible to the soak denominator and failure-rate comparison.
      'transport': transport,
      'textPreview': storedTextPreview,
    },
  );
  logChatIncoming(
    messageId: payload.id,
    fromPeerId: payload.senderPeerId,
    status: 'delivered',
    text: conversationMessage.text,
  );
  if (resultAfterSave != HandleChatMessageResult.chatMessage) {
    return (resultAfterSave, null, updatedContact);
  }
  return (HandleChatMessageResult.chatMessage, hydratedMessage, updatedContact);
}

/// 147: discriminated result of decrypting a v2 chat envelope. Kept event-free
/// so the inbox-drain decrypt-prefetch ([predecryptIncomingChatEnvelope]) and
/// the handler's inline decrypt share ONE copy of the primary + ML-KEM ring
/// logic; the handler maps these statuses to the existing flow events + return
/// values, while the prefetch silently keeps only [plaintext].
enum _V2DecryptStatus { ok, missingKey, deferred, failed, error }

class _V2ChatDecryptOutcome {
  final _V2DecryptStatus status;
  final String? plaintext;
  final bool ringFallbackUsed;
  final String? errorCode;
  final String? errorDetail;
  const _V2ChatDecryptOutcome(
    this.status, {
    this.plaintext,
    this.ringFallbackUsed = false,
    this.errorCode,
    this.errorDetail,
  });
}

/// Runs the primary ML-KEM decrypt plus the pre-restore fallback ring over a
/// parsed v2 [v2Envelope]. Pure (no flow events, no persistence); decrypt is a
/// stateless ML-KEM-768 + AES-GCM operation (go-mknoon/crypto/decrypt.go), so it
/// is safe to call concurrently / out of order.
Future<_V2ChatDecryptOutcome> _decryptV2ChatEnvelope({
  required Map<String, dynamic> v2Envelope,
  Bridge? bridge,
  String? ownMlKemSecretKey,
  List<String>? fallbackMlKemSecretKeys,
}) async {
  if (bridge == null || ownMlKemSecretKey == null) {
    return const _V2ChatDecryptOutcome(_V2DecryptStatus.missingKey);
  }
  final encrypted = v2Envelope['encrypted'] as Map<String, dynamic>;
  try {
    var decryptResult = await callDecryptMessage(
      bridge: bridge,
      ownMlKemSecretKey: ownMlKemSecretKey,
      kem: encrypted['kem'] as String,
      ciphertext: encrypted['ciphertext'] as String,
      nonce: encrypted['nonce'] as String,
    );
    var ringFallbackUsed = false;

    if (decryptResult['ok'] != true) {
      if (decryptResult['errorCode'] == 'BRIDGE_TIMEOUT') {
        return _V2ChatDecryptOutcome(
          _V2DecryptStatus.deferred,
          errorCode: decryptResult['errorCode'] as String?,
        );
      }

      for (final fallbackSecret in fallbackMlKemSecretKeys ?? const []) {
        final fallbackResult = await callDecryptMessage(
          bridge: bridge,
          ownMlKemSecretKey: fallbackSecret,
          kem: encrypted['kem'] as String,
          ciphertext: encrypted['ciphertext'] as String,
          nonce: encrypted['nonce'] as String,
        );
        if (fallbackResult['ok'] == true) {
          decryptResult = fallbackResult;
          ringFallbackUsed = true;
          break;
        }
        if (fallbackResult['errorCode'] == 'BRIDGE_TIMEOUT') {
          return _V2ChatDecryptOutcome(
            _V2DecryptStatus.deferred,
            errorCode: fallbackResult['errorCode'] as String?,
          );
        }
      }

      if (decryptResult['ok'] != true) {
        return _V2ChatDecryptOutcome(
          _V2DecryptStatus.failed,
          errorCode: decryptResult['errorCode'] as String?,
        );
      }
    }

    return _V2ChatDecryptOutcome(
      _V2DecryptStatus.ok,
      plaintext: decryptResult['plaintext'] as String,
      ringFallbackUsed: ringFallbackUsed,
    );
  } catch (e) {
    return _V2ChatDecryptOutcome(
      _V2DecryptStatus.error,
      errorDetail: e.toString(),
    );
  }
}

/// 147: decrypt-prefetch entry point for the inbox-drain bounded fan-out
/// (p2p_service_impl `_predecryptInboxChatEntries`). Returns the inner plaintext
/// JSON for a v2 chat envelope — running the SAME primary + ring decrypt the
/// handler uses — or null when [message] is not a v2 envelope, the key material
/// is unavailable, or decryption fails/defers. A null result is never a dropped
/// message: the handler re-decrypts (with full disposition) any entry omitted
/// here. Threaded to [handleIncomingChatMessage] as `predecryptedText`.
Future<String?> predecryptIncomingChatEnvelope({
  required ChatMessage message,
  Bridge? bridge,
  String? ownMlKemSecretKey,
  List<String>? fallbackMlKemSecretKeys,
}) async {
  final v2Envelope = MessagePayload.parseEncryptedEnvelope(message.content);
  if (v2Envelope == null) return null;
  final outcome = await _decryptV2ChatEnvelope(
    v2Envelope: v2Envelope,
    bridge: bridge,
    ownMlKemSecretKey: ownMlKemSecretKey,
    fallbackMlKemSecretKeys: fallbackMlKemSecretKeys,
  );
  if (outcome.ringFallbackUsed) {
    // 147/P0-B: keep the pre-restore ring-recovery breadcrumb visible even when
    // the inbox-drain prefetch (not the in-handler decrypt) recovered the
    // message. On a prefetch HIT the handler skips its own decrypt, so the
    // handler's MLKEM_RING_FALLBACK_USED at the `ok` case never fires for this
    // entry — emit it here so the live path and the drained path agree. Fires
    // exactly once per entry (a ring recovery is always a HIT → no double emit).
    emitFlowEvent(layer: 'FL', event: 'MLKEM_RING_FALLBACK_USED', details: {});
  }
  return outcome.plaintext;
}

/// 147: orchestrates the inbox-drain decrypt-prefetch for ONE staged chat entry,
/// honoring the ChatMessageListener's BLOCKED-SENDER policy. The listener rejects
/// a blocked contact's message BEFORE its own decrypt (chat_message_listener
/// `processIncomingMessage`), so the prefetch must NOT decrypt a blocked sender's
/// ciphertext into memory either — it returns null (→ no plaintext; the serial
/// loop's listener rejects the entry exactly as before, no plaintext ever
/// materialises). Also short-circuits on a missing local secret. This is the
/// production wiring helper for P2PServiceImpl.predecryptInboxChatEntry; the pure
/// envelope decrypt stays in [predecryptIncomingChatEnvelope].
Future<String?> predecryptStagedInboxChatEntry({
  required ChatMessage message,
  required ContactRepository contactRepo,
  required Bridge bridge,
  required Future<String?> Function() loadOwnMlKemSecretKey,
  required Future<List<String>> Function() loadOwnMlKemSecretKeyRing,
}) async {
  final contact = await contactRepo.getContact(message.from);
  if (contact != null && contact.isBlocked) return null;
  final secret = await loadOwnMlKemSecretKey();
  if (secret == null) return null;
  return predecryptIncomingChatEnvelope(
    message: message,
    bridge: bridge,
    ownMlKemSecretKey: secret,
    fallbackMlKemSecretKeys: await loadOwnMlKemSecretKeyRing(),
  );
}

final class _StrictIncomingMediaProjection {
  const _StrictIncomingMediaProjection.none()
    : selected = false,
      isValid = true,
      isPrivate = false,
      attachments = const <MediaAttachment>[];

  const _StrictIncomingMediaProjection.invalid()
    : selected = true,
      isValid = false,
      isPrivate = false,
      attachments = const <MediaAttachment>[];

  const _StrictIncomingMediaProjection.valid(this.attachments)
    : selected = true,
      isValid = true,
      isPrivate = false;

  /// Plan 354: exactly one v1 Protected image/video or View-Once image
  /// initial. Every other redacted policy stays invalid.
  const _StrictIncomingMediaProjection.validPrivate(this.attachments)
    : selected = true,
      isValid = true,
      isPrivate = true;

  final bool selected;
  final bool isValid;
  final bool isPrivate;
  final List<MediaAttachment> attachments;
}

_StrictIncomingMediaProjection _parseStrictIncomingMediaProjection(
  MessagePayload payload,
) {
  final media = payload.media;
  if (media == null || media.isEmpty) {
    return const _StrictIncomingMediaProjection.none();
  }
  final strictCount = media
      .where((item) => item.containsKey('blobCustody'))
      .length;
  if (strictCount == 0) return const _StrictIncomingMediaProjection.none();
  final policy = payload.privateMediaPolicy;
  // 358: a v1 disappearing initial is a strict private initial too. It reuses
  // the same atomic private stage and the same exclusive lifecycle decision;
  // only its producer matrix and its receiver-local clock differ.
  final isDisappearingInitial =
      policy.version == 1 && policy.mode == PrivateMediaMode.disappearing;
  final isPrivateInitial =
      isDisappearingInitial ||
      (policy.version == 1 &&
          (policy.mode == PrivateMediaMode.protected ||
              policy.mode == PrivateMediaMode.viewOnce));
  if (strictCount != media.length ||
      payload.isEdit ||
      (policy.requiresRedaction && !isPrivateInitial)) {
    return const _StrictIncomingMediaProjection.invalid();
  }
  try {
    final attachments = media
        .map(MediaAttachment.fromJson)
        .toList(growable: false);
    final ids = attachments.map((attachment) => attachment.id).toSet();
    final valid =
        ids.length == attachments.length &&
        !ids.contains('') &&
        attachments.every((attachment) {
          final commitment = attachment.blobCustody;
          return commitment != null &&
              commitment.isValid &&
              attachment.size > 0 &&
              attachment.contentHash == commitment.contentHash &&
              attachment.hasEncryptionMetadata;
        });
    if (!valid) return const _StrictIncomingMediaProjection.invalid();
    if (!isPrivateInitial) {
      return _StrictIncomingMediaProjection.valid(attachments);
    }
    // The receiver enforces the producer matrix independently of the wire:
    // exactly one attachment, no caption, no forward, and Protected
    // image/video or View-Once image only.
    final privateEligible =
        attachments.length == 1 &&
        payload.text.trim().isEmpty &&
        !payload.isForwarded &&
        payload.quotedMessageId == null &&
        (isDisappearingInitial
            ? disappearingMediaInitialProducerMatrixAllows(
                policyVersion: policy.version,
                mode: policy.mode,
                durationSeconds: policy.durationSeconds,
                mime: attachments.single.mime,
                mediaType: attachments.single.mediaType,
              )
            : privateMediaInitialProducerMatrixAllows(
                policyVersion: policy.version,
                mode: policy.mode,
                mime: attachments.single.mime,
                mediaType: attachments.single.mediaType,
              ));
    return privateEligible
        ? _StrictIncomingMediaProjection.validPrivate(attachments)
        : const _StrictIncomingMediaProjection.invalid();
  } on Object {
    return const _StrictIncomingMediaProjection.invalid();
  }
}

Future<bool> _isExactStrictIncomingDuplicate({
  required String messageId,
  required _StrictIncomingMediaProjection projection,
  required MediaAttachmentRepository? mediaAttachmentRepo,
}) async {
  if (!projection.isValid || mediaAttachmentRepo == null) {
    return false;
  }
  final attachmentRepo = mediaAttachmentRepo;
  if (attachmentRepo is! DirectMediaBlobCustodyRepository) return false;
  final custodyRepo = attachmentRepo as DirectMediaBlobCustodyRepository;
  final persistedAttachments = await attachmentRepo.getAttachmentsForMessage(
    messageId,
    owner: MediaOwnerLane.direct,
  );
  if (persistedAttachments.length != projection.attachments.length) {
    return false;
  }
  final persistedById = <String, MediaAttachment>{
    for (final attachment in persistedAttachments) attachment.id: attachment,
  };
  for (final incoming in projection.attachments) {
    final persisted = persistedById[incoming.id];
    if (persisted == null ||
        persisted.messageId != messageId ||
        persisted.mime != incoming.mime ||
        persisted.size != incoming.size ||
        persisted.mediaType != incoming.mediaType ||
        persisted.width != incoming.width ||
        persisted.height != incoming.height ||
        persisted.durationMs != incoming.durationMs ||
        persisted.contentHash != incoming.contentHash ||
        persisted.thumbnailHash != incoming.thumbnailHash ||
        persisted.encryptionKeyBase64 != incoming.encryptionKeyBase64 ||
        persisted.encryptionNonce != incoming.encryptionNonce ||
        persisted.encryptionScheme != incoming.encryptionScheme ||
        persisted.directMediaBlobCustodyFingerprint !=
            computeDirectMediaBlobCommitmentFingerprint(
              attachmentId: incoming.id,
              commitment: incoming.blobCustody!,
            )) {
      return false;
    }
  }

  final custodyRows = await custodyRepo.loadDirectMediaBlobCustodyForMessage(
    messageId,
  );
  if (custodyRows.isEmpty) {
    // A completed exact ACK removes v111 but retains the durable local media
    // and its one-way exact commitment fingerprint checked above.
    return persistedAttachments.every(
      (attachment) =>
          attachment.downloadStatus == kMediaDownloadStatusDone &&
          attachment.localPath != null &&
          attachment.localPath!.isNotEmpty,
    );
  }
  if (custodyRows.length != projection.attachments.length) return false;
  final custodyById = <String, DirectMediaBlobCustodyRow>{
    for (final row in custodyRows) row.attachmentId: row,
  };
  return projection.attachments.every((attachment) {
    final commitment = attachment.blobCustody!;
    final row = custodyById[attachment.id];
    return row != null &&
        row.direction == DirectMediaBlobCustodyDirection.incoming &&
        (row.state == DirectMediaBlobCustodyState.incomingCommitted ||
            row.state == DirectMediaBlobCustodyState.incomingAckPending) &&
        row.contentHash == commitment.contentHash &&
        row.ciphertextSize == commitment.ciphertextSize &&
        row.custodyKind == commitment.kind &&
        row.custodyContract == commitment.contract &&
        row.transportMime == commitment.transportMime &&
        row.expiresAtMs == commitment.expiresAtMs;
  });
}

Future<void> _repairDuplicateReplayMedia({
  required MessagePayload payload,
  required ConversationMessage existingParent,
  MediaAttachmentRepository? mediaAttachmentRepo,
  MediaFileManager? mediaFileManager,
}) async {
  if (existingParent.privateMediaPolicy.requiresRedaction &&
      (existingParent.privateMediaPolicy.isUnsupported ||
          existingParent.privateMediaState.isTerminal ||
          existingParent.hiddenAt != null ||
          existingParent.deletedAt != null)) {
    return;
  }
  final incomingMedia = payload.media;
  if (mediaAttachmentRepo == null ||
      incomingMedia == null ||
      incomingMedia.isEmpty) {
    return;
  }

  final existingAttachments = await mediaAttachmentRepo
      .getAttachmentsForMessage(payload.id, owner: MediaOwnerLane.direct);
  final existingById = {
    for (final attachment in existingAttachments) attachment.id: attachment,
  };
  var repairedCount = 0;
  for (final mediaJson in incomingMedia) {
    final incoming = MediaAttachment.fromJson(
      mediaJson,
    ).copyWith(messageId: payload.id);
    final existing = existingById[incoming.id];
    if (existing != null && _isCompleteLocalMedia(existing)) {
      continue;
    }
    if (existing == null || _isRecoverableIncomingMediaStatus(existing)) {
      // A replay that carries DIFFERENT key/nonce supersedes whatever was
      // staged under the old metadata — the new key must never be asked to
      // decrypt old bytes (112 KC-2 receive side). Drop stale staged
      // artifacts before resetting the row.
      if (existing != null &&
          mediaFileManager != null &&
          (existing.encryptionKeyBase64 != incoming.encryptionKeyBase64 ||
              existing.encryptionNonce != incoming.encryptionNonce)) {
        await _invalidateStaleStagedArtifacts(
          mediaFileManager: mediaFileManager,
          contactPeerId: payload.senderPeerId,
          existing: existing,
        );
      }
      final saved = await _saveIncomingDirectAttachment(
        repository: mediaAttachmentRepo,
        attachment: incoming,
        parent: existingParent,
        rawMediaJson: mediaJson,
        mediaFileManager: mediaFileManager,
      );
      if (saved) repairedCount++;
    }
  }

  if (repairedCount > 0) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_RECEIVE_DUPLICATE_MEDIA_REPAIR',
      details: {'id': payload.id.substring(0, 8), 'count': repairedCount},
    );
  }
}

Future<bool> _saveIncomingDirectAttachment({
  required MediaAttachmentRepository repository,
  required MediaAttachment attachment,
  required ConversationMessage parent,
  Map<String, dynamic>? rawMediaJson,
  MediaFileManager? mediaFileManager,
}) async {
  if (!parent.privateMediaPolicy.requiresRedaction) {
    await repository.saveAttachment(attachment, owner: MediaOwnerLane.direct);
    return true;
  }
  if (repository is! DirectPrivateMediaAttachmentSaveRepository) {
    return false;
  }
  final saved = await (repository as DirectPrivateMediaAttachmentSaveRepository)
      .saveDirectPrivateAttachmentGuarded(
        attachment,
        messageId: parent.id,
        nowMs: DateTime.now().toUtc().millisecondsSinceEpoch,
      );
  // 301: only a row the guarded save accepted may own a thumbnail sibling.
  // Both callers sit behind the dedup/deleted-row/replay guards, so a replay
  // of a deleted message can never reach this write.
  if (saved && rawMediaJson != null && mediaFileManager != null) {
    await _persistIncomingProtectedPhotoThumbnail(
      rawMediaJson: rawMediaJson,
      attachment: attachment,
      parent: parent,
      mediaFileManager: mediaFileManager,
    );
  }
  return saved;
}

/// 301: validates and persists the optional inline thumbnail write-once to the
/// guarded sibling path `media/<peer>/<blobId>.thumb.jpg`. The base64 is read
/// from the RAW attachment map (the model never carries it), validated
/// fail-closed (protected mode, image-and-not-gif via the dual check, decode,
/// raw cap), authorized per-callsite through [DirectPrivateMediaPathGuard],
/// and dropped after the file write — never persisted to the database.
Future<void> _persistIncomingProtectedPhotoThumbnail({
  required Map<String, dynamic> rawMediaJson,
  required MediaAttachment attachment,
  required ConversationMessage parent,
  required MediaFileManager mediaFileManager,
}) async {
  if (parent.privateMediaPolicy.mode != PrivateMediaMode.protected) return;
  final mime = attachment.mime.toLowerCase();
  final mediaType = attachment.mediaType.toLowerCase();
  if (mime == 'image/gif' || mediaType == 'gif') return;
  if (!(mime.startsWith('image/') || mediaType == 'image')) return;
  final raw = rawMediaJson[kProtectedPhotoInlineThumbnailKey];
  if (raw is! String || raw.isEmpty) return;
  final Uint8List bytes;
  try {
    bytes = base64Decode(raw);
  } catch (_) {
    return;
  }
  if (bytes.isEmpty ||
      bytes.length > kProtectedPhotoInlineThumbnailMaxRawBytes) {
    return;
  }
  if (!DirectPrivateMediaPathGuard.identifiersAreSafe(
    contactPeerId: parent.contactPeerId,
    messageId: attachment.messageId,
    attachmentId: attachment.id,
  )) {
    return;
  }
  try {
    final relative = MediaFilePathConvention.relativeThumbnailPathForAttachment(
      contactPeerId: parent.contactPeerId,
      blobId: attachment.id,
    );
    final absolutePath = await mediaFileManager.resolveStoredPath(relative);
    final authorityRoot = p.dirname(p.dirname(absolutePath));
    if (!await DirectPrivateMediaPathGuard.authorizeTarget(
      targetPath: absolutePath,
      authorityRoot: authorityRoot,
    )) {
      return;
    }
    final file = File(absolutePath);
    if (await file.exists()) return; // write-once; replay stays idempotent
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
  } catch (_) {
    // Best-effort: a failed thumbnail write never blocks the message.
  }
}

ConversationMessage _seedIncomingPrivateMediaLifecycle(
  ConversationMessage message, {
  ConversationMessage? existingMessage,
}) {
  final existing = existingMessage;
  // Every existing redacted checkpoint is monotonic, not only terminal ones.
  // Same-ID edits/replays must never reset opening/viewing to `available`,
  // switch policy, clear reveal/terminal timestamps, or reintroduce text.
  if (existing != null && existing.privateMediaPolicy.requiresRedaction) {
    return message.copyWith(
      text: '',
      hiddenAt: existing.hiddenAt,
      deletedAt: existing.deletedAt,
      deletedByPeerId: existing.deletedByPeerId,
      privateMediaPolicy: existing.privateMediaPolicy,
      privateMediaState: existing.privateMediaState,
      privateMediaReceivedAtMs: existing.privateMediaReceivedAtMs,
      privateMediaExpiresAtMs: existing.privateMediaExpiresAtMs,
      privateMediaRevealedAtMs: existing.privateMediaRevealedAtMs,
      privateMediaTerminalAtMs: existing.privateMediaTerminalAtMs,
      privateMediaClockHighWaterMs: existing.privateMediaClockHighWaterMs,
    );
  }

  final policy = message.privateMediaPolicy;
  if (!policy.requiresRedaction) return message;

  final nowMs = DateTime.now().millisecondsSinceEpoch;
  final receivedAtMs = existing?.privateMediaReceivedAtMs ?? nowMs;
  final existingHighWater = existing?.privateMediaClockHighWaterMs ?? 0;
  final highWaterMs = existingHighWater > nowMs ? existingHighWater : nowMs;
  final expiresAtMs =
      policy.mode == PrivateMediaMode.disappearing &&
          policy.durationSeconds != null
      ? receivedAtMs + policy.durationSeconds! * 1000
      : null;
  return message.copyWith(
    text: '',
    privateMediaState: policy.initialState,
    privateMediaReceivedAtMs: receivedAtMs,
    privateMediaExpiresAtMs: expiresAtMs,
    privateMediaRevealedAtMs: null,
    privateMediaTerminalAtMs: null,
    privateMediaClockHighWaterMs: highWaterMs,
  );
}

/// Deletes staged download artifacts (`.enc`/`.part`) that were produced
/// under a superseded key/nonce. Paths derive from the EXISTING row's mime —
/// that is the metadata the artifact was staged under.
Future<void> _invalidateStaleStagedArtifacts({
  required MediaFileManager mediaFileManager,
  required String contactPeerId,
  required MediaAttachment existing,
}) async {
  if (!DirectPrivateMediaPathGuard.identifiersAreSafe(
    contactPeerId: contactPeerId,
    messageId: existing.messageId,
    attachmentId: existing.id,
  )) {
    return;
  }
  late final String absolutePath;
  try {
    absolutePath = await mediaFileManager.localPathForAttachment(
      contactPeerId: contactPeerId,
      blobId: existing.id,
      mime: existing.mime,
    );
  } catch (_) {
    return;
  }
  final root = p.dirname(p.dirname(absolutePath));
  final targets = [File('$absolutePath.enc'), File('$absolutePath.part')];
  for (final target in targets) {
    if (!await DirectPrivateMediaPathGuard.authorizeTarget(
      targetPath: target.path,
      authorityRoot: root,
    )) {
      return;
    }
  }
  for (final target in targets) {
    await deleteAppOwnedMediaFileIfExists(
      file: target,
      caller: 'handleIncomingChatMessage.invalidateStaleStagedArtifacts',
      reason: 'duplicate_replay_key_rotation',
      details: {
        'attachmentId': existing.id,
        'messageId': existing.messageId,
        'mime': existing.mime,
        'downloadStatus': existing.downloadStatus,
      },
      swallowErrors: true,
    );
  }
}

bool _isCompleteLocalMedia(MediaAttachment attachment) {
  return attachment.downloadStatus == 'done' &&
      attachment.localPath != null &&
      attachment.localPath!.isNotEmpty;
}

bool _isRecoverableIncomingMediaStatus(MediaAttachment attachment) {
  return attachment.downloadStatus == 'pending' ||
      attachment.downloadStatus == 'downloading' ||
      attachment.downloadStatus == 'failed' ||
      attachment.downloadStatus == 'integrity_failed';
}

bool _isHiddenIncomingEditPlaceholder(ConversationMessage message) {
  return message.isIncoming &&
      message.isHidden &&
      !message.isDeleted &&
      !message.privateMediaPolicy.requiresRedaction &&
      message.editedAt != null;
}

bool _isIncomingDeletedPlaceholder(ConversationMessage message) {
  return message.isIncoming && message.isDeleted;
}

/// Outcome of the single exclusive strict-private receive decision.
enum _StrictPrivateReceiveDecision {
  /// The durable parent vanished after the atomic stage: nothing is published
  /// and no receipt is owed.
  parentRemoved,

  /// A terminal owner won: durable zero-effect supersession plus one receipt.
  terminal,

  /// Presentation completed under the same lifecycle authority.
  published,
}

/// Runs [action] under the incumbent repository-wide exclusive private
/// lifecycle lease when the repository owns one.
///
/// Nested repository acquisitions inside [action] are reentrant, and the lease
/// is never upgraded from an exact-ID section.
Future<T> _underPrivateLifecycleAuthority<T>(
  MediaAttachmentRepository? mediaAttachmentRepo,
  Future<T> Function() action,
) {
  final runtime = mediaAttachmentRepo;
  if (runtime is DirectPrivateMediaCleanupRuntime) {
    return (runtime as DirectPrivateMediaCleanupRuntime)
        .directPrivateMediaLifecycleLock
        .synchronizedAll(action);
  }
  return action();
}

/// True for a durable incoming v1 Protected/View-Once parent that has already
/// reached a terminal disposition.
///
/// Only these replays bypass generic duplicate handling; an active
/// available/opening/viewing parent keeps its existing path.
bool _isDurableStrictPrivateTerminalParent(ConversationMessage message) =>
    message.isIncoming &&
    message.privateMediaPolicy.requiresRedaction &&
    (message.deletedAt != null ||
        message.hiddenAt != null ||
        message.privateMediaState == PrivateMediaLifecycleState.consumed ||
        message.privateMediaState == PrivateMediaLifecycleState.expired);

/// Immutable wire identity one ACTIVE strict-private replay must still prove
/// against its durable parent, BEFORE any canonicalization may reuse that
/// parent's durable lifecycle columns.
///
/// The mutable receiver-local clock is deliberately absent: preserving it is
/// exactly what this barrier protects. What must agree is the authored
/// identity — including the private mode and its duration, which decide which
/// modality (and therefore which custody owner) this message belongs to.
bool _matchesActiveStrictPrivateReplayIdentity({
  required ConversationMessage durable,
  required ConversationMessage wire,
}) =>
    durable.isIncoming &&
    durable.id == wire.id &&
    durable.contactPeerId == wire.contactPeerId &&
    durable.senderPeerId == wire.senderPeerId &&
    durable.timestamp == wire.timestamp &&
    durable.dedupKey == wire.dedupKey &&
    durable.quotedMessageId == wire.quotedMessageId &&
    durable.isForwarded == wire.isForwarded &&
    durable.editedAt == null &&
    durable.text.isEmpty &&
    durable.privateMediaPolicy == wire.privateMediaPolicy &&
    durable.privateMediaMode == wire.privateMediaMode &&
    durable.privateMediaDurationSeconds == wire.privateMediaDurationSeconds;

/// The complete immutable public commitment one ACTIVE strict-private replay
/// must still prove against its durable v111 obligation.
///
/// Source/relay and retry metadata are deliberately excluded: they belong to
/// the receiver's own download attempts, not to the replayed wire event.
bool _sameStrictPrivateCustodyCommitment(
  DirectMediaBlobCustodyRow durable,
  DirectMediaBlobCustodyRow wire,
) =>
    durable.attachmentId == wire.attachmentId &&
    durable.messageId == wire.messageId &&
    durable.direction == wire.direction &&
    durable.custodyKind == wire.custodyKind &&
    durable.custodyContract == wire.custodyContract &&
    durable.contentHash == wire.contentHash &&
    durable.ciphertextSize == wire.ciphertextSize &&
    durable.transportMime == wire.transportMime &&
    durable.expiresAtMs == wire.expiresAtMs;

/// The hydrated durable attachment identity an ACTIVE replay must match.
///
/// The repository hydrates the RAW key from secure storage, so this compares
/// the actual key material rather than a storage reference. Any drift refuses
/// before the nested stage can overwrite the secure slot.
bool _sameHydratedStrictPrivateAttachment(
  MediaAttachment durable,
  MediaAttachment wire,
) =>
    durable.id == wire.id &&
    durable.messageId == wire.messageId &&
    durable.mime == wire.mime &&
    durable.size == wire.size &&
    durable.mediaType == wire.mediaType &&
    durable.width == wire.width &&
    durable.height == wire.height &&
    durable.durationMs == wire.durationMs &&
    durable.contentHash == wire.contentHash &&
    durable.encryptionKeyBase64 == wire.encryptionKeyBase64 &&
    durable.encryptionNonce == wire.encryptionNonce &&
    durable.encryptionScheme == wire.encryptionScheme;

ConversationMessage _buildHiddenIncomingEditPlaceholder({
  required MessagePayload payload,
  String? transport,
}) {
  final editedAt = payload.editedAt ?? payload.timestamp;
  return payload
      .toConversationMessage(
        contactPeerId: payload.senderPeerId,
        isIncoming: true,
        status: 'delivered',
        editedAt: editedAt,
        transport: transport,
      )
      .copyWith(hiddenAt: editedAt);
}

ConversationMessage _materializeIncomingOriginalFromHiddenEdit({
  required ConversationMessage hiddenEditMessage,
  required MessagePayload payload,
  String? transport,
}) {
  final original = payload.toConversationMessage(
    contactPeerId: payload.senderPeerId,
    isIncoming: true,
    status: 'delivered',
    transport: transport,
  );
  return original.copyWith(
    text: hiddenEditMessage.text,
    createdAt: hiddenEditMessage.createdAt,
    editedAt: hiddenEditMessage.editedAt,
    quotedMessageId:
        hiddenEditMessage.quotedMessageId ?? original.quotedMessageId,
    transport: transport ?? hiddenEditMessage.transport ?? original.transport,
    hiddenAt: null,
  );
}

ConversationMessage _mergeIncomingOriginalIntoDeletedPlaceholder({
  required ConversationMessage deletedMessage,
  required MessagePayload payload,
  String? transport,
}) {
  final original = payload.toConversationMessage(
    contactPeerId: payload.senderPeerId,
    isIncoming: true,
    status: deletedMessage.status,
    transport: transport,
  );
  return original.copyWith(
    text: '',
    createdAt: deletedMessage.createdAt,
    editedAt: deletedMessage.editedAt,
    quotedMessageId: deletedMessage.quotedMessageId ?? original.quotedMessageId,
    deletedAt: deletedMessage.deletedAt,
    deletedByPeerId: deletedMessage.deletedByPeerId,
    hiddenAt: deletedMessage.hiddenAt,
    transport: transport ?? deletedMessage.transport ?? original.transport,
    media: const [],
  );
}

bool _isIncomingEditNewer({
  required String incomingEditedAt,
  required String currentEditedAt,
}) {
  final incoming = DateTime.tryParse(incomingEditedAt);
  final current = DateTime.tryParse(currentEditedAt);
  if (incoming != null && current != null) {
    return incoming.isAfter(current);
  }
  return incomingEditedAt.compareTo(currentEditedAt) > 0;
}
