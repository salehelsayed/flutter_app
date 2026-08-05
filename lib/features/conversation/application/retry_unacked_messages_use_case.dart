import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
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

bool _isOutgoingOneMoreLookPrivate(ConversationMessage message) =>
    !message.isIncoming &&
    message.privateMediaPolicy.version == 1 &&
    (message.privateMediaMode == PrivateMediaMode.protected ||
        message.privateMediaMode == PrivateMediaMode.viewOnce);
