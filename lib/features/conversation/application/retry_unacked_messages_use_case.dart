import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/database/direct_inbox_event_envelope.dart';
import 'package:flutter_app/core/database/outgoing_transport_mutation.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/features/conversation/application/delete_message_tombstone_visibility.dart';
import 'package:flutter_app/features/conversation/application/outbound_envelope_policy.dart';
import 'package:flutter_app/features/conversation/application/outgoing_direct_private_transport_settlement.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/direct_private_media_lifecycle_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';

/// Retries outgoing messages stuck in 'sent' status by storing them
/// in the relay inbox using the persisted wire_envelope.
///
/// This is inbox-only -- no direct send, no re-encrypt, no media rebuild.
/// Once successfully stored, status moves to 'inboxed' and wire_envelope is
/// retained until a delivery receipt proves receiver-side delivery.
///
/// Returns the count of successfully updated messages.
Future<int> retryUnackedMessages({
  required MessageRepository messageRepo,
  required P2PService p2pService,
  MediaAttachmentRepository? mediaAttachmentRepo,
  // 186 (FU-185-A): the anti-race window. The periodic pass keeps the default
  // 60s (a genuinely in-flight recent send may still get its ack); the
  // reconnect pass passes Duration.zero so a freshly-queued offline message
  // converges as soon as we are back online instead of after the 5-min tick.
  Duration olderThan = const Duration(seconds: 60),
}) async {
  final retryStopwatch = Stopwatch()..start();
  void emitRetryTiming({
    required String outcome,
    required int total,
    required int delivered,
  }) {
    emitFlowEvent(
      layer: 'FL',
      event: 'RETRY_UNACKED_MESSAGES_TIMING',
      details: {
        'elapsedMs': retryStopwatch.elapsedMilliseconds,
        'outcome': outcome,
        'total': total,
        'delivered': delivered,
      },
    );
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'RETRY_UNACKED_MESSAGES_START',
    details: {},
  );

  final unacked = await messageRepo.getUnackedOutgoingMessages(
    olderThan: olderThan,
  );

  if (unacked.isEmpty) {
    emitFlowEvent(
      layer: 'FL',
      event: 'RETRY_UNACKED_MESSAGES_NONE',
      details: {},
    );
    emitRetryTiming(outcome: 'none', total: 0, delivered: 0);
    return 0;
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'RETRY_UNACKED_MESSAGES_FOUND',
    details: {'count': unacked.length},
  );

  var count = 0;
  for (final msg in unacked) {
    // 361: a fanout-marked generation is owned by its exact surviving v108
    // siblings (or is terminal with zero siblings). The single-target unacked
    // rebuild must refuse it before any legacy network, capability or not.
    if (msg.directEventFanoutGenerationId != null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'RETRY_UNACKED_SKIPPED_FANOUT_GENERATION',
        details: {'id': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id},
      );
      continue;
    }

    // A persisted fresh-media preparation token is exclusive authority. An
    // unacked snapshot carrying it must never reach the legacy bool inbox
    // store or any ordinary/private settlement writer, even if its v108 row
    // is temporarily absent or the repository lacks the custody capability.
    if (msg.directMediaCustodyIntentId != null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'RETRY_UNACKED_DIRECT_MEDIA_CUSTODY_PREPARATION_OWNED',
        details: {'id': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id},
      );
      continue;
    }

    if (await _mustSkipOwnedOrCorruptUnackedMutation(
      message: msg,
      messageRepo: messageRepo,
      phase: 'loaded',
    )) {
      continue;
    }

    // A v108 row is the sole owner of its immutable initial chat envelope
    // (text or ordinary media). Generic bool storage cannot prove the
    // ACK-or-expiry contract and must not settle it. Skip only this row so
    // unrelated legacy messages in the same batch continue to converge.
    if (messageRepo is OutgoingDirectTextInboxCustodyRepository) {
      try {
        final owned =
            await (messageRepo as OutgoingDirectTextInboxCustodyRepository)
                .loadDirectInboxCustodyOwnerForMessageId(messageId: msg.id);
        if (owned != null) {
          emitFlowEvent(
            layer: 'FL',
            event: 'RETRY_UNACKED_DIRECT_INBOX_CUSTODY_OWNED',
            details: {
              'id': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id,
            },
          );
          continue;
        }
      } catch (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'RETRY_UNACKED_DIRECT_INBOX_CUSTODY_LOOKUP_FAILED',
          details: {
            'id': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id,
            'errorType': error.runtimeType.toString(),
          },
        );
        continue;
      }
    }

    // Defensive: skip messages with null or empty wireEnvelope.
    // The SQL query should exclude these, but a corrupt row or future
    // query change could let one through.
    if (msg.wireEnvelope == null || msg.wireEnvelope!.isEmpty) {
      emitFlowEvent(
        layer: 'FL',
        event: 'RETRY_UNACKED_MESSAGE_SKIP_NULL_ENVELOPE',
        details: {'id': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id},
      );
      continue;
    }

    final isOutgoingPrivate = _isOutgoingOneMoreLookPrivate(msg);
    final isPrivateDeleteTombstone = isOutgoingPrivate && msg.isDeleted;
    final ordinaryTransportRepository =
        messageRepo is OutgoingTransportMutationRepository
        ? messageRepo as OutgoingTransportMutationRepository
        : null;
    final privateDeleteRepository =
        messageRepo is DirectPrivateDeleteForEveryoneRepository
        ? messageRepo as DirectPrivateDeleteForEveryoneRepository
        : null;
    List<MediaAttachment>? privateAttachments;
    if (isPrivateDeleteTombstone && privateDeleteRepository == null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'RETRY_UNACKED_PRIVATE_DELETE_CAPABILITY_MISSING',
        details: {'id': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id},
      );
      continue;
    }
    if (isOutgoingPrivate && !isPrivateDeleteTombstone) {
      if (mediaAttachmentRepo == null ||
          messageRepo is! OutgoingDirectPrivateEnvelopeCustodyRepository ||
          mediaAttachmentRepo is! OutgoingDirectPrivateMutationRepository) {
        emitFlowEvent(
          layer: 'FL',
          event: 'RETRY_UNACKED_PRIVATE_SETTLEMENT_CAPABILITY_MISSING',
          details: {'id': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id},
        );
        continue;
      }
      try {
        privateAttachments = await mediaAttachmentRepo.getAttachmentsForMessage(
          msg.id,
          owner: MediaOwnerLane.direct,
        );
      } catch (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'RETRY_UNACKED_PRIVATE_ATTACHMENT_LOAD_FAILED',
          details: {
            'id': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id,
            'error': error.runtimeType.toString(),
          },
        );
        continue;
      }
      if (privateAttachments.length > 1) {
        emitFlowEvent(
          layer: 'FL',
          event: 'RETRY_UNACKED_PRIVATE_ATTACHMENT_IDENTITY_REFUSED',
          details: {'id': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id},
        );
        continue;
      }
    }
    if (!isOutgoingPrivate && ordinaryTransportRepository == null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'RETRY_UNACKED_ORDINARY_SETTLEMENT_CAPABILITY_MISSING',
        details: {'id': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id},
      );
      continue;
    }

    Future<bool> persistTransport({
      required String status,
      required String? transport,
    }) async {
      if (isPrivateDeleteTombstone) {
        final target = normalizeOutgoingDeleteTombstoneVisibility(
          msg.copyWith(status: status, transport: transport),
        );
        final settled = await privateDeleteRepository!
            .settlePrivateDeleteForEveryoneTombstone(
              tombstone: target,
              expectedEnvelope: msg.wireEnvelope!,
            );
        if (settled == null) {
          emitFlowEvent(
            layer: 'FL',
            event: 'RETRY_UNACKED_PRIVATE_DELETE_SETTLEMENT_REFUSED',
            details: {
              'id': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id,
              'status': status,
            },
          );
        }
        return settled != null;
      }
      if (isOutgoingPrivate) {
        final outcome =
            await settleOutgoingDirectPrivateTransportUnderLifecycleLock(
              messageRepository: messageRepo,
              mediaAttachmentRepository: mediaAttachmentRepo,
              attachments: privateAttachments,
              messageId: msg.id,
              expectedEnvelope: msg.wireEnvelope!,
              status: status,
              transport: transport,
              relayExpiresAt: null,
            );
        if (!outcome.accepted) {
          emitFlowEvent(
            layer: 'FL',
            event: 'RETRY_UNACKED_PRIVATE_TRANSPORT_SETTLEMENT_REFUSED',
            details: {
              'id': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id,
              'status': status,
            },
          );
        }
        return outcome.accepted;
      }
      final result = msg.isDeleted
          ? await ordinaryTransportRepository!
                .settleOutgoingOrdinaryDeleteTombstone(
                  messageId: msg.id,
                  expectedContactPeerId: msg.contactPeerId,
                  expectedEnvelope: msg.wireEnvelope!,
                  status: status,
                  transport: transport,
                  relayExpiresAt: null,
                  mode: OutgoingOrdinarySettlementMode.live,
                )
          : await ordinaryTransportRepository!.settleOutgoingOrdinaryTransport(
              messageId: msg.id,
              expectedContactPeerId: msg.contactPeerId,
              expectedEnvelope: msg.wireEnvelope!,
              status: status,
              transport: transport,
              relayExpiresAt: null,
              mode: OutgoingOrdinarySettlementMode.live,
            );
      return result.outcome.authorizesTransport;
    }

    // The batch row is only a snapshot. Re-read exact transport identity
    // immediately before either quarantine/settlement or relay egress so a
    // direct-media preparation that won after list load cannot be replayed by
    // this legacy lane. Re-check global v108 ownership after the parent read
    // as well, covering the token -> combined-custody transition.
    try {
      final fresh = await messageRepo.getMessage(msg.id);
      if (!_isExactUnackedTransportCandidate(loaded: msg, fresh: fresh)) {
        emitFlowEvent(
          layer: 'FL',
          event: 'RETRY_UNACKED_MESSAGE_SKIP_STALE_SNAPSHOT',
          details: {'id': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id},
        );
        continue;
      }
      if (await _mustSkipOwnedOrCorruptUnackedMutation(
        message: fresh!,
        messageRepo: messageRepo,
        phase: 'egress',
      )) {
        continue;
      }
      if (messageRepo is OutgoingDirectTextInboxCustodyRepository) {
        final owner =
            await (messageRepo as OutgoingDirectTextInboxCustodyRepository)
                .loadDirectInboxCustodyOwnerForMessageId(messageId: msg.id);
        if (owner != null) {
          emitFlowEvent(
            layer: 'FL',
            event: 'RETRY_UNACKED_DIRECT_INBOX_CUSTODY_OWNED_AT_EGRESS',
            details: {
              'id': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id,
            },
          );
          continue;
        }
      }
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'RETRY_UNACKED_EGRESS_AUTHORITY_RECHECK_FAILED',
        details: {
          'id': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id,
          'errorType': error.runtimeType.toString(),
        },
      );
      continue;
    }

    if (isUnsafeLegacyOutboundEnvelope(msg.wireEnvelope!)) {
      if (isOutgoingPrivate) {
        await persistTransport(status: 'failed', transport: null);
      } else {
        await ordinaryTransportRepository!
            .quarantineUnsafeLegacyOutgoingEnvelope(
              messageId: msg.id,
              expectedContactPeerId: msg.contactPeerId,
              expectedEnvelope: msg.wireEnvelope!,
              isDeleteTombstone: msg.isDeleted,
            );
      }
      emitFlowEvent(
        layer: 'FL',
        event: 'RETRY_UNACKED_MESSAGE_SKIP_LEGACY_WIRE_ENVELOPE',
        details: {'id': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id},
      );
      continue;
    }
    try {
      final stored = await p2pService.storeInInbox(
        msg.contactPeerId,
        msg.wireEnvelope!,
      );
      if (stored) {
        final persisted = await persistTransport(
          status: 'inboxed',
          transport: 'inbox',
        );
        if (persisted) {
          count++;
          emitFlowEvent(
            layer: 'FL',
            event: 'RETRY_UNACKED_MESSAGE_INBOXED',
            details: {
              'id': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id,
            },
          );
        }
      }
      // Not stored -> leave as 'sent', retry on next online transition
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'RETRY_UNACKED_MESSAGE_ERROR',
        details: {
          'id': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id,
          'error': e.toString(),
        },
      );
    }
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'RETRY_UNACKED_MESSAGES_COMPLETE',
    details: {'total': unacked.length, 'delivered': count},
  );
  emitRetryTiming(outcome: 'complete', total: unacked.length, delivered: count);

  return count;
}

Future<bool> _mustSkipOwnedOrCorruptUnackedMutation({
  required ConversationMessage message,
  required MessageRepository messageRepo,
  required String phase,
}) async {
  final envelope = message.wireEnvelope;
  if (envelope == null || envelope.isEmpty) return false;
  final classified = classifyDirectInboxEventEnvelope(envelope);
  if (classified == null || !classified.isMutation) return false;
  // 356: ownership is a property of the shared v109 outbox, not of whichever
  // owner staged the event. A private deletion is staged by the private owner,
  // so casting through the text-stage capability would miss it entirely.
  final lifecycleCapability =
      messageRepo is DirectMutationInboxCustodyLifecycleRepository
      ? messageRepo as DirectMutationInboxCustodyLifecycleRepository
      : null;
  final repository =
      lifecycleCapability?.supportsDirectMutationInboxCustodyLifecycle == true
      ? lifecycleCapability
      : null;
  try {
    final owner = repository == null
        ? null
        : await repository.loadDirectTextMutationInboxCustodyForEvent(
            recipientPeerId: message.contactPeerId,
            eventId: classified.eventId,
          );
    if (owner != null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'RETRY_UNACKED_DIRECT_MUTATION_CUSTODY_OWNED',
        details: {
          'id': message.id.length > 8 ? message.id.substring(0, 8) : message.id,
          'phase': phase,
        },
      );
      return true;
    }
    // Current event-bearing deletions have no pre-349 compatibility shape.
    // An ownerless exact edit may be a pre-349 cached event and retains its
    // historical exact-envelope fallback.
    return classified.kind == DirectInboxEventEnvelopeKind.deletion;
  } catch (error) {
    emitFlowEvent(
      layer: 'FL',
      event: 'RETRY_UNACKED_DIRECT_MUTATION_CUSTODY_LOOKUP_FAILED',
      details: {
        'id': message.id.length > 8 ? message.id.substring(0, 8) : message.id,
        'phase': phase,
        'errorType': error.runtimeType.toString(),
      },
    );
    return true;
  }
}

bool _isOutgoingOneMoreLookPrivate(ConversationMessage message) =>
    !message.isIncoming &&
    message.privateMediaPolicy.version == 1 &&
    (message.privateMediaMode == PrivateMediaMode.protected ||
        message.privateMediaMode == PrivateMediaMode.viewOnce);

bool _isExactUnackedTransportCandidate({
  required ConversationMessage loaded,
  required ConversationMessage? fresh,
}) =>
    fresh != null &&
    !fresh.isIncoming &&
    fresh.status == 'sent' &&
    fresh.directMediaCustodyIntentId == null &&
    // 361/362: a fanout-marked generation (blob-free OR linked media) is
    // owned by its exact surviving v108 siblings or is terminal. The loaded
    // batch already skipped marked rows; a marker acquired between list load
    // and egress must equally never enter this singular resend.
    fresh.directEventFanoutGenerationId == null &&
    fresh.id == loaded.id &&
    fresh.contactPeerId == loaded.contactPeerId &&
    fresh.senderPeerId == loaded.senderPeerId &&
    fresh.wireEnvelope == loaded.wireEnvelope &&
    fresh.isDeleted == loaded.isDeleted &&
    fresh.deletedAt == loaded.deletedAt &&
    fresh.deletedByPeerId == loaded.deletedByPeerId &&
    fresh.hiddenAt == loaded.hiddenAt &&
    fresh.privateMediaPolicy.version == loaded.privateMediaPolicy.version &&
    fresh.privateMediaMode == loaded.privateMediaMode &&
    fresh.privateMediaDurationSeconds == loaded.privateMediaDurationSeconds;
