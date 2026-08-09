import 'dart:async';

import 'package:clock/clock.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/database/direct_media_blob_custody.dart';
import 'package:flutter_app/core/database/helpers/media_attachments_db_helpers.dart'
    show OutgoingDirectDeletionLane;
import 'package:flutter_app/core/database/outgoing_transport_mutation.dart';
import 'package:flutter_app/core/media/direct_media_blob_terminalization.dart';
import 'package:flutter_app/core/media/direct_private_media_path_guard.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_file_path_convention.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/private_media_lifecycle_engine.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/application/delete_message_tombstone_visibility.dart';
import 'package:flutter_app/features/conversation/application/drain_direct_reaction_inbox_custody_outbox_use_case.dart';
import 'package:flutter_app/features/conversation/application/outgoing_live_deadline.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/direct_private_media_lifecycle.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_reaction_inbox_custody_outbox_entry.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/message_deletion_payload.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/direct_private_media_lifecycle_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';

const Uuid _deletionUuid = Uuid();

Future<int> deleteMessageForMe({
  required ConversationMessage message,
  required MessageRepository messageRepo,
  ReactionRepository? reactionRepo,
  MediaAttachmentRepository? mediaAttachmentRepo,
  MediaFileManager? mediaFileManager,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'CHAT_MSG_DELETE_FOR_ME_START',
    details: {
      'id': message.id.length > 8 ? message.id.substring(0, 8) : message.id,
    },
  );

  // Authority boundary: the caller may hold a stale row snapshot. Branching
  // on it can physically delete a durable private tombstone and let replay
  // resurrect the message, so re-read the exact current parent first.
  ConversationMessage? currentMessage;
  try {
    currentMessage = await messageRepo.getMessage(message.id);
  } catch (error) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_DELETE_FOR_ME_AUTHORITY_READ_FAILED',
      details: {'error': error.runtimeType.toString()},
    );
    return 0;
  }
  if (currentMessage == null ||
      currentMessage.id != message.id ||
      currentMessage.contactPeerId != message.contactPeerId ||
      currentMessage.senderPeerId != message.senderPeerId ||
      currentMessage.isIncoming != message.isIncoming) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_DELETE_FOR_ME_AUTHORITY_UNAVAILABLE',
      details: {
        'id': message.id.length > 8 ? message.id.substring(0, 8) : message.id,
      },
    );
    return 0;
  }

  if (currentMessage.privateMediaPolicy.requiresRedaction) {
    final lifecycleRepository = messageRepo;
    final attachments = mediaAttachmentRepo;
    if (lifecycleRepository is! DirectPrivateMediaLifecycleRepository ||
        attachments is! DirectPrivateMediaCleanupRepository ||
        attachments is! DirectPrivateMediaCleanupRuntime ||
        mediaFileManager == null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_PRIVATE_DELETE_FOR_ME_UNAVAILABLE',
        details: {
          'id': message.id.length > 8 ? message.id.substring(0, 8) : message.id,
        },
      );
      return 0;
    }
    final directLifecycleRepository =
        lifecycleRepository as DirectPrivateMediaLifecycleRepository;
    final cleanupRuntime = attachments as DirectPrivateMediaCleanupRuntime;
    final attachmentRepository = attachments as MediaAttachmentRepository;
    final now = DateTime.now().toUtc();
    final hidden = await directLifecycleRepository.hidePrivateMediaForMe(
      currentMessage.id,
      hiddenAt: now.toIso8601String(),
      nowMs: now.millisecondsSinceEpoch,
    );
    if (!hidden) return 0;
    await reactionRepo?.deleteReactionsForMessage(currentMessage.id);
    final adapter = DirectPrivateMediaLifecycle(
      messageRepository: directLifecycleRepository,
      mediaAttachmentRepository: attachmentRepository,
      mediaFileManager: mediaFileManager,
    );
    final engine = PrivateMediaLifecycleEngine(
      adapter: adapter,
      lifecycleLock: cleanupRuntime.directPrivateMediaLifecycleLock,
      nowMs: () => DateTime.now().toUtc().millisecondsSinceEpoch,
    );
    try {
      await engine.cleanupTerminalMessage(currentMessage.id);
    } catch (error) {
      // The hidden parent is the durable delete claim. Startup/resume recovery
      // retries raw file/key/row cleanup without resurrecting the message.
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_PRIVATE_DELETE_FOR_ME_CLEANUP_RETAINED',
        details: {'error': error.runtimeType.toString()},
      );
    }
    return 1;
  }

  if (!await _authorizeOutgoingDirectMediaBlobParentDeletion(
    messageId: currentMessage.id,
    mediaAttachmentRepo: mediaAttachmentRepo,
  )) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_DELETE_FOR_ME_BLOB_CUSTODY_RETAINED',
      details: {'id': _messageIdPreview(currentMessage.id)},
    );
    return 0;
  }
  await cleanupDeletedMessageArtifacts(
    message: currentMessage,
    reactionRepo: reactionRepo,
    mediaAttachmentRepo: mediaAttachmentRepo,
    mediaFileManager: mediaFileManager,
  );
  final count = await messageRepo.deleteMessage(currentMessage.id);

  emitFlowEvent(
    layer: 'FL',
    event: 'CHAT_MSG_DELETE_FOR_ME_DONE',
    details: {'count': count},
  );

  return count;
}

class _DeletionWireEnvelopeEncryptFailed implements Exception {
  const _DeletionWireEnvelopeEncryptFailed(this.errorCode);

  final Object? errorCode;
}

Future<String> buildDeletionWireEnvelope({
  required Bridge bridge,
  required ConversationMessage originalMessage,
  required String deletedAt,
  required String recipientMlKemPublicKey,
  String? eventId,
}) async {
  final payload = MessageDeletionPayload(
    messageId: originalMessage.id,
    senderPeerId: originalMessage.senderPeerId,
    timestamp: deletedAt,
    eventId: eventId,
  );
  final innerJson = payload.toInnerJson();
  final encryptResult = await callEncryptMessage(
    bridge: bridge,
    recipientMlKemPublicKey: recipientMlKemPublicKey,
    plaintext: innerJson,
  );
  if (encryptResult['ok'] != true) {
    throw _DeletionWireEnvelopeEncryptFailed(encryptResult['errorCode']);
  }
  return MessageDeletionPayload.buildEncryptedEnvelope(
    senderPeerId: originalMessage.senderPeerId,
    kem: encryptResult['kem'] as String,
    ciphertext: encryptResult['ciphertext'] as String,
    nonce: encryptResult['nonce'] as String,
    eventId: eventId,
  );
}

Future<(SendChatMessageResult, ConversationMessage?)> deleteMessageForEveryone({
  required P2PService p2pService,
  required MessageRepository messageRepo,
  required ConversationMessage originalMessage,
  ReactionRepository? reactionRepo,
  MediaAttachmentRepository? mediaAttachmentRepo,
  MediaFileManager? mediaFileManager,
  Bridge? bridge,
  String? recipientMlKemPublicKey,
  StoreInAckCustodyInboxDetailedFn? storeInAckCustodyInboxDetailed,
  bool emitTimingEvent = true,
}) async {
  final deleteStopwatch = clock.stopwatch()..start();
  final liveDeadline = OutgoingLiveDeadline(() => deleteStopwatch.elapsed);
  final hasMedia = originalMessage.media.isNotEmpty;
  void emitDeleteTiming({
    required String outcome,
    Map<String, dynamic> details = const {},
  }) {
    if (!emitTimingEvent) return;
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_DELETE_FOR_EVERYONE_TIMING',
      details: {
        'elapsedMs': deleteStopwatch.elapsedMilliseconds,
        'outcome': outcome,
        'hadMedia': hasMedia,
        ...details,
      },
    );
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'CHAT_MSG_DELETE_FOR_EVERYONE_START',
    details: {
      'id': originalMessage.id.length > 8
          ? originalMessage.id.substring(0, 8)
          : originalMessage.id,
    },
  );

  ConversationMessage? currentMessage;
  try {
    currentMessage = await messageRepo.getMessage(originalMessage.id);
  } catch (error) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_DELETE_FOR_EVERYONE_AUTHORITY_READ_FAILED',
      details: {'error': error.runtimeType.toString()},
    );
    emitDeleteTiming(outcome: 'authority_read_failed');
    return (SendChatMessageResult.sendFailed, null);
  }
  if (currentMessage == null ||
      currentMessage.id != originalMessage.id ||
      currentMessage.contactPeerId != originalMessage.contactPeerId ||
      currentMessage.senderPeerId != originalMessage.senderPeerId ||
      currentMessage.isIncoming != originalMessage.isIncoming) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_DELETE_FOR_EVERYONE_AUTHORITY_UNAVAILABLE',
      details: {'id': _messageIdPreview(originalMessage.id)},
    );
    emitDeleteTiming(outcome: 'authority_unavailable');
    return (SendChatMessageResult.invalidMessage, null);
  }

  // 'inboxed' rows hold a durable relay copy the receiver will drain —
  // delete-for-everyone must stay available for them (doc 115 P1).
  if (currentMessage.isIncoming ||
      currentMessage.isDeleted ||
      (currentMessage.status != 'delivered' &&
          currentMessage.status != 'inboxed')) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_DELETE_FOR_EVERYONE_INVALID',
      details: {
        'status': currentMessage.status,
        'isIncoming': currentMessage.isIncoming,
        'isDeleted': currentMessage.isDeleted,
      },
    );
    emitDeleteTiming(outcome: 'invalid_message');
    return (SendChatMessageResult.invalidMessage, null);
  }

  final requiresPrivateTerminalCleanup =
      !currentMessage.isIncoming &&
      currentMessage.privateMediaPolicy.version == 1 &&
      (currentMessage.privateMediaMode == PrivateMediaMode.protected ||
          currentMessage.privateMediaMode == PrivateMediaMode.viewOnce);
  final ordinaryTransportRepository =
      messageRepo is OutgoingTransportMutationRepository
      ? messageRepo as OutgoingTransportMutationRepository
      : null;
  final mutationCustodyCapability =
      messageRepo is OutgoingDirectTextMutationInboxCustodyRepository
      ? messageRepo as OutgoingDirectTextMutationInboxCustodyRepository
      : null;
  final mutationCustodyRepository =
      mutationCustodyCapability?.supportsDirectTextMutationInboxCustody == true
      ? mutationCustodyCapability
      : null;
  // The media lane stages its own event, so it needs only the shared v109
  // load/failure/completion owner — not the text stage capability.
  final mutationLifecycleCapability =
      messageRepo is DirectMutationInboxCustodyLifecycleRepository
      ? messageRepo as DirectMutationInboxCustodyLifecycleRepository
      : null;
  final mutationLifecycleRepository =
      mutationLifecycleCapability
              ?.supportsDirectMutationInboxCustodyLifecycle ==
          true
      ? mutationLifecycleCapability
      : null;
  final ackCustodyStoreCapability = p2pService is AckOrExpiryInboxStore
      ? p2pService as AckOrExpiryInboxStore
      : null;
  final availableStrictMutationStore =
      storeInAckCustodyInboxDetailed ??
      ackCustodyStoreCapability?.storeInAckCustodyInboxDetailed;
  final StoreInAckCustodyInboxDetailedFn strictMutationStore =
      availableStrictMutationStore ??
      (
        String toPeerId,
        String message, {
        required AckCustodyKind custodyKind,
        int? timeoutMs,
      }) async => const InboxStoreOutcome(
        status: InboxStoreStatus.failed,
        errorCode: 'ACK_OR_EXPIRY_STORE_UNAVAILABLE',
      );
  final laneCapability =
      mediaAttachmentRepo is OutgoingDirectDeletionLaneRepository
      ? mediaAttachmentRepo as OutgoingDirectDeletionLaneRepository
      : null;
  final laneRepository =
      laneCapability?.supportsOutgoingDirectDeletionLaneSelection == true
      ? laneCapability
      : null;
  final mediaDeletionCapability =
      mediaAttachmentRepo is OutgoingDirectMediaDeletionInboxCustodyRepository
      ? mediaAttachmentRepo as OutgoingDirectMediaDeletionInboxCustodyRepository
      : null;
  final mediaDeletionRepository =
      mediaDeletionCapability?.supportsDirectMediaDeletionInboxCustody == true
      ? mediaDeletionCapability
      : null;

  // Lane selection is DB-authoritative. The parent's in-memory media list is a
  // UI snapshot, and the v110 intent is deliberately cleared once v108 staging
  // consumes it, so neither can decide which owner may delete this parent.
  final ordinaryPolicyParent =
      !requiresPrivateTerminalCleanup &&
      currentMessage.privateMediaPolicy.version == 0 &&
      currentMessage.privateMediaMode == PrivateMediaMode.ordinary &&
      currentMessage.directMediaCustodyIntentId == null;
  OutgoingDirectDeletionLane? selectedLane;
  if (ordinaryPolicyParent && laneRepository != null) {
    try {
      selectedLane = await laneRepository.selectOutgoingDirectDeletionLane(
        currentMessage.id,
      );
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_DELETE_FOR_EVERYONE_LANE_SELECT_ERROR',
        details: {'errorType': error.runtimeType.toString()},
      );
      emitDeleteTiming(outcome: 'lane_select_error');
      return (SendChatMessageResult.invalidMessage, null);
    }
    if (selectedLane == OutgoingDirectDeletionLane.contradiction) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_DELETE_FOR_EVERYONE_BLOB_CUSTODY_RETAINED',
        details: {'id': _messageIdPreview(currentMessage.id)},
      );
      emitDeleteTiming(outcome: 'blob_custody_retained');
      return (SendChatMessageResult.invalidMessage, null);
    }
  }
  final ownsDirectTextMutationInboxCustody =
      ordinaryPolicyParent &&
      (selectedLane == null
          ? currentMessage.media.isEmpty
          : selectedLane == OutgoingDirectDeletionLane.text);
  final ownsDirectMediaDeletionInboxCustody =
      selectedLane == OutgoingDirectDeletionLane.strictMedia;
  if (!requiresPrivateTerminalCleanup && ordinaryTransportRepository == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_DELETE_FOR_EVERYONE_ORDINARY_AUTHORITY_UNAVAILABLE',
      details: {'id': _messageIdPreview(originalMessage.id)},
    );
    emitDeleteTiming(outcome: 'ordinary_authority_unavailable');
    return (SendChatMessageResult.invalidMessage, null);
  }

  if (ownsDirectTextMutationInboxCustody && mutationCustodyRepository == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_DELETE_FOR_EVERYONE_MUTATION_CUSTODY_UNAVAILABLE',
      details: {'reason': 'missing_mutation_custody_repository'},
    );
    emitDeleteTiming(outcome: 'mutation_custody_unavailable');
    return (SendChatMessageResult.sendFailed, null);
  }

  if (ownsDirectMediaDeletionInboxCustody &&
      (mediaDeletionRepository == null ||
          mutationLifecycleRepository == null)) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_DELETE_FOR_EVERYONE_MUTATION_CUSTODY_UNAVAILABLE',
      details: {'reason': 'missing_media_deletion_repository'},
    );
    emitDeleteTiming(outcome: 'mutation_custody_unavailable');
    return (SendChatMessageResult.sendFailed, null);
  }

  // Both v109 lanes retain their exact authenticated event before any network
  // request, so a stopped node is no longer a pre-authority refusal for them.
  final ownsDirectMutationInboxCustody =
      ownsDirectTextMutationInboxCustody || ownsDirectMediaDeletionInboxCustody;
  final nodeWasNotRunningAtEntry = !p2pService.currentState.isStarted;
  if (nodeWasNotRunningAtEntry && !ownsDirectMutationInboxCustody) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_DELETE_FOR_EVERYONE_NODE_NOT_RUNNING',
      details: {},
    );
    emitDeleteTiming(outcome: 'node_not_running');
    return (SendChatMessageResult.nodeNotRunning, null);
  }

  final recipientKey = recipientMlKemPublicKey?.trim();
  if (bridge == null || recipientKey == null || recipientKey.isEmpty) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_DELETE_FOR_EVERYONE_ENCRYPTION_REQUIRED',
      details: {
        'reason': bridge == null ? 'missing_bridge' : 'missing_recipient_key',
      },
    );
    emitDeleteTiming(
      outcome: 'encryption_required',
      details: {
        'reason': bridge == null ? 'missing_bridge' : 'missing_recipient_key',
      },
    );
    return (SendChatMessageResult.encryptionRequired, null);
  }

  final deletedAt = clock.now().toUtc().toIso8601String();
  // Identity is minted only after a v109-owning lane has been selected. A
  // legacy or historical parent must never carry an event id its transport
  // cannot retain.
  final mutationEventId = ownsDirectMutationInboxCustody
      ? _deletionUuid.v4()
      : null;

  final privateLifecycleRepository =
      messageRepo is DirectPrivateMediaLifecycleRepository
      ? messageRepo as DirectPrivateMediaLifecycleRepository
      : null;
  final privateCleanupRuntime =
      mediaAttachmentRepo is DirectPrivateMediaCleanupRuntime
      ? mediaAttachmentRepo as DirectPrivateMediaCleanupRuntime
      : null;
  final privateCleanupRepository =
      mediaAttachmentRepo is DirectPrivateMediaCleanupRepository
      ? mediaAttachmentRepo as DirectPrivateMediaCleanupRepository
      : null;
  final privateDeleteRepository =
      messageRepo is DirectPrivateDeleteForEveryoneRepository
      ? messageRepo as DirectPrivateDeleteForEveryoneRepository
      : null;
  if (requiresPrivateTerminalCleanup &&
      (privateLifecycleRepository == null ||
          privateCleanupRuntime == null ||
          privateCleanupRepository == null ||
          privateDeleteRepository == null ||
          mediaFileManager == null)) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_PRIVATE_DELETE_FOR_EVERYONE_UNAVAILABLE',
      details: {'id': _messageIdPreview(originalMessage.id)},
    );
    emitDeleteTiming(outcome: 'private_cleanup_unavailable');
    return (SendChatMessageResult.sendFailed, null);
  }
  String jsonString;
  try {
    jsonString = await buildDeletionWireEnvelope(
      bridge: bridge,
      originalMessage: currentMessage,
      deletedAt: deletedAt,
      recipientMlKemPublicKey: recipientKey,
      eventId: mutationEventId,
    );
  } on _DeletionWireEnvelopeEncryptFailed catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_DELETE_FOR_EVERYONE_ENCRYPT_FAILED',
      details: {'errorCode': e.errorCode},
    );
    emitDeleteTiming(
      outcome: 'encrypt_failed',
      details: {'errorCode': e.errorCode},
    );
    return (SendChatMessageResult.sendFailed, null);
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_DELETE_FOR_EVERYONE_ENCRYPT_ERROR',
      details: {'error': e.toString()},
    );
    emitDeleteTiming(outcome: 'encrypt_error');
    return (SendChatMessageResult.sendFailed, null);
  }

  if (!requiresPrivateTerminalCleanup &&
      selectedLane == null &&
      !await _authorizeOutgoingDirectMediaBlobParentDeletion(
        messageId: currentMessage.id,
        mediaAttachmentRepo: mediaAttachmentRepo,
      )) {
    // Legacy authorization path, retained only while no DB-authoritative lane
    // selector is wired. When one is, the atomic stage below owns every v111
    // decision and no cleanup precedes stage authorization.
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_DELETE_FOR_EVERYONE_BLOB_CUSTODY_RETAINED',
      details: {'id': _messageIdPreview(currentMessage.id)},
    );
    emitDeleteTiming(outcome: 'blob_custody_retained');
    return (SendChatMessageResult.invalidMessage, null);
  }

  final builtPendingTombstone = buildDeletedMessageTombstone(
    originalMessage: currentMessage,
    deletedAt: deletedAt,
    deletedByPeerId: currentMessage.senderPeerId,
    hiddenLocally: false,
    status: 'sending',
    transport: currentMessage.transport,
    wireEnvelope: jsonString,
  );
  // The original message's inbox transport proves custody only for its chat
  // envelope, never for this newly minted deletion envelope. Clear it before
  // the private update-only commit; transport is restored only by an actual
  // deletion send or inbox deposit below.
  final pendingTombstoneCandidate = builtPendingTombstone.copyWith(
    transport: null,
    relayExpiresAt: null,
    custodyCheckedAt: null,
  );
  late final ConversationMessage pendingTombstone;
  DirectReactionInboxCustodyOutboxEntry? stagedMutationCustody;
  if (requiresPrivateTerminalCleanup) {
    final committed = await privateDeleteRepository!
        .commitPrivateDeleteForEveryoneTombstone(
          expectedMessage: currentMessage,
          tombstone: pendingTombstoneCandidate,
        );
    if (committed == null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_PRIVATE_DELETE_FOR_EVERYONE_COMMIT_PRESERVED',
        details: {'id': _messageIdPreview(currentMessage.id)},
      );
      emitDeleteTiming(outcome: 'private_commit_preserved');
      return (SendChatMessageResult.invalidMessage, null);
    }
    pendingTombstone = committed;
  } else if (ownsDirectMediaDeletionInboxCustody) {
    final staged = await mediaDeletionRepository!
        .stageOutgoingDirectMediaDeletionInboxCustody(
          expected: currentMessage,
          staged: pendingTombstoneCandidate,
          kind: OutgoingOrdinaryAttemptKind.tombstoneInitial,
          recipientPeerId: currentMessage.contactPeerId,
          eventId: mutationEventId!,
          wireEnvelope: jsonString,
        );
    final committedCustody = staged.custody;
    if (!staged.authorizesTransport ||
        committedCustody == null ||
        staged.message == null) {
      // There is no fallback after strict selection: a refusal leaves the
      // parent, v111 and v108 exactly as they were.
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_DELETE_FOR_EVERYONE_MUTATION_COMMIT_PRESERVED',
        details: {'id': _messageIdPreview(currentMessage.id)},
      );
      emitDeleteTiming(outcome: 'mutation_commit_preserved');
      return (SendChatMessageResult.invalidMessage, null);
    }
    pendingTombstone = staged.message!;
    stagedMutationCustody = committedCustody;
    jsonString = committedCustody.wireEnvelope;
  } else if (ownsDirectTextMutationInboxCustody) {
    final staged = await mutationCustodyRepository!
        .stageOutgoingDirectTextMutationInboxCustody(
          expected: currentMessage,
          staged: pendingTombstoneCandidate,
          kind: OutgoingOrdinaryAttemptKind.tombstoneInitial,
          recipientPeerId: currentMessage.contactPeerId,
          eventId: mutationEventId!,
          wireEnvelope: jsonString,
        );
    final committedCustody = staged.custody;
    if (!staged.authorizesTransport || committedCustody == null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_DELETE_FOR_EVERYONE_MUTATION_COMMIT_PRESERVED',
        details: {'id': _messageIdPreview(currentMessage.id)},
      );
      emitDeleteTiming(outcome: 'mutation_commit_preserved');
      return (SendChatMessageResult.invalidMessage, null);
    }
    pendingTombstone = staged.message!;
    stagedMutationCustody = committedCustody;
    jsonString = committedCustody.wireEnvelope;
  } else {
    final staged = await ordinaryTransportRepository!
        .stageOutgoingOrdinaryAttempt(
          expected: currentMessage,
          staged: pendingTombstoneCandidate,
          kind: OutgoingOrdinaryAttemptKind.tombstoneInitial,
        );
    if (!staged.authorizesTransport) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_DELETE_FOR_EVERYONE_ORDINARY_COMMIT_PRESERVED',
        details: {'id': _messageIdPreview(currentMessage.id)},
      );
      emitDeleteTiming(outcome: 'ordinary_commit_preserved');
      return (SendChatMessageResult.invalidMessage, null);
    }
    pendingTombstone = staged.message!;
  }

  if (requiresPrivateTerminalCleanup) {
    await reactionRepo?.deleteReactionsForMessage(pendingTombstone.id);
    final adapter = DirectPrivateMediaLifecycle(
      messageRepository: privateLifecycleRepository!,
      mediaAttachmentRepository: mediaAttachmentRepo!,
      mediaFileManager: mediaFileManager!,
    );
    final engine = PrivateMediaLifecycleEngine(
      adapter: adapter,
      lifecycleLock: privateCleanupRuntime!.directPrivateMediaLifecycleLock,
      nowMs: () => DateTime.now().toUtc().millisecondsSinceEpoch,
    );
    try {
      // The durable deleted_at tombstone is the terminal authority. Exact
      // lifecycle cleanup (not generic attachment deletion) discards any
      // deferred completion and removes file/key/row state under that claim.
      await engine.cleanupTerminalMessage(pendingTombstone.id);
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_PRIVATE_DELETE_FOR_EVERYONE_CLEANUP_RETAINED',
        details: {'error': error.runtimeType.toString()},
      );
    }
  } else {
    await _bestEffortCleanup(
      message: pendingTombstone,
      reactionRepo: reactionRepo,
      mediaAttachmentRepo: mediaAttachmentRepo,
      mediaFileManager: mediaFileManager,
    );
  }

  if (nodeWasNotRunningAtEntry && ownsDirectMutationInboxCustody) {
    ConversationMessage? authoritative = pendingTombstone;
    try {
      final settled = await ordinaryTransportRepository!
          .settleOutgoingOrdinaryDeleteTombstone(
            messageId: pendingTombstone.id,
            expectedContactPeerId: pendingTombstone.contactPeerId,
            expectedEnvelope: jsonString,
            status: 'failed',
            transport: null,
            relayExpiresAt: null,
            mode: OutgoingOrdinarySettlementMode.live,
          );
      authoritative = settled.message ?? authoritative;
    } catch (_) {
      // The exact event owner and visible tombstone are already durable.
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_DELETE_FOR_EVERYONE_NODE_NOT_RUNNING',
      details: const {'custodyStaged': true},
    );
    emitDeleteTiming(
      outcome: 'node_not_running',
      details: const {'custodyStaged': true},
    );
    return (SendChatMessageResult.nodeNotRunning, authoritative);
  }

  Future<bool>? mutationCustodyHedge;
  if (ownsDirectMutationInboxCustody) {
    final custody = stagedMutationCustody!;
    mutationCustodyHedge =
        drainOwnedDirectMutationInboxCustodyOutboxEntry(
          entry: custody,
          custodyRepository: mutationLifecycleRepository!,
          storeInAckCustodyInboxDetailed: strictMutationStore,
        ).catchError((Object error) {
          emitFlowEvent(
            layer: 'FL',
            event: 'CHAT_MSG_DELETE_MUTATION_CUSTODY_HEDGE_ERROR',
            details: {'errorType': error.runtimeType.toString()},
          );
          return false;
        });
    unawaited(mutationCustodyHedge);
  }

  final targetPeerId = currentMessage.contactPeerId;
  final isAlreadyConnected = p2pService.currentState.connections.any(
    (connection) => connection.peerId == targetPeerId,
  );

  if (isAlreadyConnected) {
    try {
      final timeoutMs = liveDeadline.allocateCommittedSendTimeoutMs();
      if (timeoutMs != null) {
        final sendResult = await p2pService.sendMessageWithReply(
          targetPeerId,
          jsonString,
          timeoutMs: timeoutMs,
        );
        if (sendResult.sent) {
          return _completeSuccessfulDeleteSend(
            p2pService: p2pService,
            messageRepo: messageRepo,
            tombstone: pendingTombstone,
            targetPeerId: targetPeerId,
            jsonString: jsonString,
            provesDeviceDelivery: sendResult.acked == true,
            via: _resolveDeleteTransport(
              p2pService,
              targetPeerId,
              sendResult,
              preserveLocalPeerLabel: true,
            ),
            isOutgoingPrivate: requiresPrivateTerminalCleanup,
            ownsDirectMutationInboxCustody: ownsDirectMutationInboxCustody,
            emitTimingEvent: emitTimingEvent,
            deleteStopwatch: deleteStopwatch,
          );
        }
      }
    } catch (_) {
      // Fall through to the normal race.
    }
  }

  final isLocalPeer = p2pService.isLocalPeer(targetPeerId);
  final raceFutures = <Future<_DeleteRaceResult>>[];
  if (isLocalPeer) {
    raceFutures.add(
      _tryLocalDeleteSend(
        p2pService,
        targetPeerId,
        jsonString,
        currentMessage.senderPeerId,
        timeoutMs: interactiveLocalBudget.inMilliseconds,
      ),
    );
  }
  raceFutures.add(
    _tryDirectDeleteSend(
      p2pService,
      targetPeerId,
      jsonString,
      liveDeadline: liveDeadline,
    ).timeout(
      liveDeadline.remaining,
      onTimeout: () => _DeleteRaceResult.failed('direct_timeout'),
    ),
  );

  final completer = Completer<_DeleteRaceResult>();
  var pendingCount = raceFutures.length;
  final failures = <_DeleteRaceResult>[];
  final writtenResults = <_DeleteRaceResult>[];

  void completeWithoutProof() {
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
    if (writtenResults.isNotEmpty) {
      final written = writtenResults.first;
      completer.complete(
        _DeleteRaceResult.succeeded(
          via: written.via!,
          authenticated: written.authenticated,
          explicitlyAcked: written.explicitlyAcked,
          reason: failureReason,
          relayProbeEligible: relayProbeEligible,
        ),
      );
      return;
    }
    completer.complete(
      _DeleteRaceResult.failed(
        failureReason,
        relayProbeEligible: relayProbeEligible,
      ),
    );
  }

  for (final future in raceFutures) {
    future
        .then((result) {
          if (result.provesDeviceDeliveryForCurrentProtocol &&
              !completer.isCompleted) {
            completer.complete(result);
          } else {
            if (result.success) {
              writtenResults.add(result);
            } else {
              failures.add(result);
            }
            pendingCount--;
            if (pendingCount <= 0 && !completer.isCompleted) {
              completeWithoutProof();
            }
          }
        })
        .catchError((Object e) {
          failures.add(_DeleteRaceResult.failed(e.toString()));
          pendingCount--;
          if (pendingCount <= 0 && !completer.isCompleted) {
            completeWithoutProof();
          }
        });
  }

  final raceResult = await completer.future;
  if (raceResult.provesDeviceDeliveryForCurrentProtocol) {
    return _completeSuccessfulDeleteSend(
      p2pService: p2pService,
      messageRepo: messageRepo,
      tombstone: pendingTombstone,
      targetPeerId: targetPeerId,
      jsonString: jsonString,
      provesDeviceDelivery: true,
      via: raceResult.via!,
      isOutgoingPrivate: requiresPrivateTerminalCleanup,
      ownsDirectMutationInboxCustody: ownsDirectMutationInboxCustody,
      emitTimingEvent: emitTimingEvent,
      deleteStopwatch: deleteStopwatch,
    );
  }

  var failureReason = raceResult.reason ?? 'unknown';
  var writtenResult = raceResult.success ? raceResult : null;
  if (raceResult.relayProbeEligible) {
    final relayProbeResult = await _tryRelayProbeDeleteSend(
      p2pService,
      targetPeerId,
      jsonString,
      failureReason: failureReason,
      liveDeadline: liveDeadline,
    );
    if (relayProbeResult.provesDeviceDeliveryForCurrentProtocol) {
      return _completeSuccessfulDeleteSend(
        p2pService: p2pService,
        messageRepo: messageRepo,
        tombstone: pendingTombstone,
        targetPeerId: targetPeerId,
        jsonString: jsonString,
        provesDeviceDelivery: true,
        via: relayProbeResult.via!,
        isOutgoingPrivate: requiresPrivateTerminalCleanup,
        ownsDirectMutationInboxCustody: ownsDirectMutationInboxCustody,
        emitTimingEvent: emitTimingEvent,
        deleteStopwatch: deleteStopwatch,
      );
    }
    if (relayProbeResult.success) writtenResult = relayProbeResult;
    failureReason = relayProbeResult.reason ?? failureReason;
  }

  if (writtenResult != null) {
    return _completeSuccessfulDeleteSend(
      p2pService: p2pService,
      messageRepo: messageRepo,
      tombstone: pendingTombstone,
      targetPeerId: targetPeerId,
      jsonString: jsonString,
      provesDeviceDelivery: false,
      via: writtenResult.via!,
      isOutgoingPrivate: requiresPrivateTerminalCleanup,
      ownsDirectMutationInboxCustody: ownsDirectMutationInboxCustody,
      emitTimingEvent: emitTimingEvent,
      deleteStopwatch: deleteStopwatch,
    );
  }

  // The protected mutation store starts beside the live race and never delays
  // an authenticated device ACK. Once every live leg has failed, however, its
  // already-running acceptance is the only successful transport outcome and
  // must be reflected to the caller instead of reporting peerNotFound while
  // the exact tombstone has already converged to durable inbox custody.
  if (ownsDirectMutationInboxCustody &&
      mutationCustodyHedge != null &&
      await mutationCustodyHedge) {
    ConversationMessage? convergedTombstone;
    try {
      convergedTombstone = await messageRepo.getMessage(pendingTombstone.id);
    } catch (_) {
      // Protected relay acceptance already retired the exact event. A failed
      // publication read cannot revoke that custody transfer.
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_DELETE_FOR_EVERYONE_SUCCESS',
      details: {
        'id': _messageIdPreview(originalMessage.id),
        'status': convergedTombstone?.status ?? 'preserved',
        'via': convergedTombstone?.transport ?? 'inbox',
      },
    );
    emitDeleteTiming(
      outcome: 'success',
      details: {
        'status': convergedTombstone?.status ?? 'preserved',
        'via': convergedTombstone?.transport ?? 'inbox',
      },
    );
    return (SendChatMessageResult.success, convergedTombstone);
  }

  if (!ownsDirectMutationInboxCustody) {
    try {
      final storedInInbox = await p2pService.storeInInbox(
        targetPeerId,
        jsonString,
      );
      if (storedInInbox) {
        // Inbox acceptance is custody, not delivery (doc 115 D-3): the
        // tombstone stays 'inboxed' + VISIBLE with the envelope retained until
        // a deletion delivery receipt confirms the receiver applied it.
        final inboxedTombstone = normalizeOutgoingDeleteTombstoneVisibility(
          pendingTombstone.copyWith(
            status: 'inboxed',
            transport: 'inbox',
            wireEnvelope: jsonString,
          ),
        );
        final persisted = await _persistOutgoingDeleteTombstoneResult(
          messageRepo: messageRepo,
          tombstone: inboxedTombstone,
          expectedEnvelope: jsonString,
          isOutgoingPrivate: requiresPrivateTerminalCleanup,
        );
        emitFlowEvent(
          layer: 'FL',
          event: 'CHAT_MSG_DELETE_FOR_EVERYONE_SUCCESS',
          details: {
            'id': _messageIdPreview(originalMessage.id),
            'via': 'inbox',
          },
        );
        emitDeleteTiming(
          outcome: 'success',
          details: {'status': 'inboxed', 'via': 'inbox'},
        );
        return (SendChatMessageResult.success, persisted);
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_DELETE_FOR_EVERYONE_INBOX_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  final failedTombstone = normalizeOutgoingDeleteTombstoneVisibility(
    pendingTombstone.copyWith(
      status: 'failed',
      transport: requiresPrivateTerminalCleanup
          ? null
          : pendingTombstone.transport,
      wireEnvelope: jsonString,
    ),
  );
  final persistedFailedTombstone = await _persistOutgoingDeleteTombstoneResult(
    messageRepo: messageRepo,
    tombstone: failedTombstone,
    expectedEnvelope: jsonString,
    isOutgoingPrivate: requiresPrivateTerminalCleanup,
  );
  emitFlowEvent(
    layer: 'FL',
    event: 'CHAT_MSG_DELETE_FOR_EVERYONE_FAILED',
    details: {
      'id': _messageIdPreview(originalMessage.id),
      'reason': failureReason,
    },
  );
  emitDeleteTiming(
    outcome: 'failed',
    details: {
      'reason': failureReason,
      'result': _resultForDeleteFailureReason(failureReason).name,
    },
  );
  return (
    _resultForDeleteFailureReason(failureReason),
    persistedFailedTombstone,
  );
}

ConversationMessage buildDeletedMessageTombstone({
  required ConversationMessage originalMessage,
  required String deletedAt,
  required String deletedByPeerId,
  required bool hiddenLocally,
  required String status,
  String? transport,
  String? wireEnvelope,
}) {
  return originalMessage.copyWith(
    text: '',
    status: status,
    deletedAt: deletedAt,
    deletedByPeerId: deletedByPeerId,
    hiddenAt: hiddenLocally ? deletedAt : null,
    transport: transport ?? originalMessage.transport,
    wireEnvelope: wireEnvelope,
    media: const <MediaAttachment>[],
  );
}

Future<void> cleanupDeletedMessageArtifacts({
  required ConversationMessage message,
  ReactionRepository? reactionRepo,
  MediaAttachmentRepository? mediaAttachmentRepo,
  MediaFileManager? mediaFileManager,
}) async {
  if (!message.isIncoming &&
      message.privateMediaPolicy.version == 1 &&
      (message.privateMediaMode == PrivateMediaMode.protected ||
          message.privateMediaMode == PrivateMediaMode.viewOnce)) {
    throw StateError(
      'private message artifacts require terminal lifecycle cleanup',
    );
  }
  final attachments =
      await mediaAttachmentRepo?.getAttachmentsForMessage(
        message.id,
        owner: MediaOwnerLane.direct,
      ) ??
      const <MediaAttachment>[];
  final storedPaths = attachments
      .map((attachment) => attachment.localPath)
      .whereType<String>()
      .toList(growable: false);

  await mediaAttachmentRepo?.markUploadPendingAttachmentsFailedForMessage(
    message.id,
    owner: MediaOwnerLane.direct,
  );
  await reactionRepo?.deleteReactionsForMessage(message.id);
  await mediaAttachmentRepo?.deleteAttachmentsForMessage(
    message.id,
    owner: MediaOwnerLane.direct,
  );

  if (mediaFileManager == null) return;
  for (final storedPath in storedPaths) {
    if (!_isOwnedMessageStoredPath(storedPath, message.id)) {
      continue;
    }
    final resolvedPath = await mediaFileManager.resolveStoredPath(storedPath);
    await mediaFileManager.deleteFile(resolvedPath);
  }
  // 301: incoming protected rows may own an inline-thumbnail sibling even
  // though localPath is still null (pre-open). This function is the DISTINCT
  // third destructive path (incoming delete-for-everyone) — remove the
  // sibling with the row so no decrypted pixels outlive the message.
  for (final attachment in attachments) {
    if (!DirectPrivateMediaPathGuard.identifiersAreSafe(
      contactPeerId: message.contactPeerId,
      messageId: message.id,
      attachmentId: attachment.id,
    )) {
      continue;
    }
    final thumbnailPath = await mediaFileManager.resolveStoredPath(
      MediaFilePathConvention.relativeThumbnailPathForAttachment(
        contactPeerId: message.contactPeerId,
        blobId: attachment.id,
      ),
    );
    await mediaFileManager.deleteFile(thumbnailPath);
  }
}

Future<bool> _authorizeOutgoingDirectMediaBlobParentDeletion({
  required String messageId,
  required MediaAttachmentRepository? mediaAttachmentRepo,
}) async {
  if (mediaAttachmentRepo is! DirectMediaBlobCustodyRepository) return true;
  final custodyRepository =
      mediaAttachmentRepo as DirectMediaBlobCustodyRepository;
  if (!custodyRepository.supportsDirectMediaBlobCustody) return true;
  if (mediaAttachmentRepo
      is! OutgoingDirectMediaBlobTerminalizationRepository) {
    return false;
  }
  final terminalizationRepository =
      mediaAttachmentRepo as OutgoingDirectMediaBlobTerminalizationRepository;
  if (!terminalizationRepository
      .supportsOutgoingDirectMediaBlobTerminalization) {
    return false;
  }
  return custodyRepository.runDirectMediaBlobCustodyLifecycle(() async {
    final rows = await custodyRepository.loadDirectMediaBlobCustodyForMessage(
      messageId,
    );
    final outgoingRows = rows
        .where(
          (row) => row.direction == DirectMediaBlobCustodyDirection.outgoing,
        )
        .toList(growable: false);
    if (outgoingRows.length != rows.length) return false;
    if (outgoingRows.isNotEmpty) {
      final outcome = await terminalizationRepository
          .terminalizeOutgoingDirectMediaBlobGenerationIfExact(
            expectedRows: outgoingRows,
            reason: DirectMediaBlobTerminalizationReason.explicitCancellation,
            nowMs: DateTime.now().toUtc().millisecondsSinceEpoch,
          );
      if (!outcome.permitsParentDeletion) return false;
    }

    // Publish a durable cancellation marker while the same exclusive lease is
    // still held. If no v111 row existed at the first read, a fresh producer
    // entering afterwards must fail its exact attachment projection check.
    await mediaAttachmentRepo!.markUploadPendingAttachmentsFailedForMessage(
      messageId,
      owner: MediaOwnerLane.direct,
    );
    return true;
  });
}

Future<void> _bestEffortCleanup({
  required ConversationMessage message,
  ReactionRepository? reactionRepo,
  MediaAttachmentRepository? mediaAttachmentRepo,
  MediaFileManager? mediaFileManager,
}) async {
  try {
    await cleanupDeletedMessageArtifacts(
      message: message,
      reactionRepo: reactionRepo,
      mediaAttachmentRepo: mediaAttachmentRepo,
      mediaFileManager: mediaFileManager,
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_DELETE_ARTIFACT_CLEANUP_ERROR',
      details: {
        'id': message.id.length > 8 ? message.id.substring(0, 8) : message.id,
        'error': e.toString(),
      },
    );
  }
}

class _DeleteRaceResult {
  final bool success;
  final bool authenticated;
  final bool explicitlyAcked;
  final String? via;
  final String? reason;
  final bool relayProbeEligible;

  bool get provesDeviceDeliveryForCurrentProtocol =>
      success && authenticated && explicitlyAcked;

  const _DeleteRaceResult._({
    required this.success,
    this.authenticated = false,
    this.explicitlyAcked = false,
    this.via,
    this.reason,
    this.relayProbeEligible = false,
  });

  factory _DeleteRaceResult.succeeded({
    required String via,
    required bool authenticated,
    bool explicitlyAcked = false,
    String? reason,
    bool relayProbeEligible = false,
  }) => _DeleteRaceResult._(
    success: true,
    authenticated: authenticated,
    explicitlyAcked: explicitlyAcked,
    via: via,
    reason: reason,
    relayProbeEligible: relayProbeEligible,
  );

  factory _DeleteRaceResult.failed(
    String reason, {
    bool relayProbeEligible = false,
  }) => _DeleteRaceResult._(
    success: false,
    reason: reason,
    relayProbeEligible: relayProbeEligible,
  );
}

Future<(SendChatMessageResult, ConversationMessage?)>
_completeSuccessfulDeleteSend({
  required P2PService p2pService,
  required MessageRepository messageRepo,
  required ConversationMessage tombstone,
  required String targetPeerId,
  required String jsonString,
  required bool provesDeviceDelivery,
  required String via,
  required bool isOutgoingPrivate,
  required bool ownsDirectMutationInboxCustody,
  required bool emitTimingEvent,
  required Stopwatch deleteStopwatch,
}) async {
  final message = await _persistOutgoingDeleteResult(
    p2pService: p2pService,
    targetPeerId: targetPeerId,
    jsonString: jsonString,
    provesDeviceDelivery: provesDeviceDelivery,
    tombstone: tombstone,
    via: via,
    allowLegacyInboxFallback: !ownsDirectMutationInboxCustody,
  );
  final persisted = await _persistOutgoingDeleteTombstoneResult(
    messageRepo: messageRepo,
    tombstone: message,
    expectedEnvelope: jsonString,
    isOutgoingPrivate: isOutgoingPrivate,
  );

  emitFlowEvent(
    layer: 'FL',
    event: 'CHAT_MSG_DELETE_FOR_EVERYONE_SUCCESS',
    details: {
      'id': _messageIdPreview(tombstone.id),
      'status': message.status,
      'via': message.transport,
    },
  );
  if (emitTimingEvent) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CHAT_MSG_DELETE_FOR_EVERYONE_TIMING',
      details: {
        'elapsedMs': deleteStopwatch.elapsedMilliseconds,
        'outcome': 'success',
        'hadMedia': false,
        'status': message.status,
        'via': message.transport,
      },
    );
  }
  return (SendChatMessageResult.success, persisted);
}

Future<ConversationMessage?> _persistOutgoingDeleteTombstoneResult({
  required MessageRepository messageRepo,
  required ConversationMessage tombstone,
  required String expectedEnvelope,
  required bool isOutgoingPrivate,
}) async {
  if (isOutgoingPrivate) {
    if (messageRepo is! DirectPrivateDeleteForEveryoneRepository) return null;
    return (messageRepo as DirectPrivateDeleteForEveryoneRepository)
        .settlePrivateDeleteForEveryoneTombstone(
          tombstone: tombstone,
          expectedEnvelope: expectedEnvelope,
        );
  }
  if (messageRepo is! OutgoingTransportMutationRepository) return null;
  final result = await (messageRepo as OutgoingTransportMutationRepository)
      .settleOutgoingOrdinaryDeleteTombstone(
        messageId: tombstone.id,
        expectedContactPeerId: tombstone.contactPeerId,
        expectedEnvelope: expectedEnvelope,
        status: tombstone.status,
        transport: tombstone.transport,
        relayExpiresAt: tombstone.relayExpiresAt,
        mode: OutgoingOrdinarySettlementMode.live,
      );
  return switch (result.outcome) {
    OutgoingOrdinaryMutationOutcome.applied ||
    OutgoingOrdinaryMutationOutcome.idempotent ||
    OutgoingOrdinaryMutationOutcome.preserved => result.message,
    OutgoingOrdinaryMutationOutcome.removed ||
    OutgoingOrdinaryMutationOutcome.refused => null,
  };
}

Future<ConversationMessage> _persistOutgoingDeleteResult({
  required P2PService p2pService,
  required String targetPeerId,
  required String jsonString,
  required bool provesDeviceDelivery,
  required ConversationMessage tombstone,
  required String via,
  required bool allowLegacyInboxFallback,
}) async {
  if (provesDeviceDelivery) {
    return normalizeOutgoingDeleteTombstoneVisibility(
      tombstone.copyWith(
        status: 'delivered',
        transport: via,
        wireEnvelope: null,
      ),
    );
  }

  if (!allowLegacyInboxFallback) {
    return normalizeOutgoingDeleteTombstoneVisibility(
      tombstone.copyWith(
        status: 'sent',
        transport: via,
        wireEnvelope: jsonString,
      ),
    );
  }

  try {
    final storedInInbox = await p2pService.storeInInbox(
      targetPeerId,
      jsonString,
    );
    if (storedInInbox) {
      // Custody, not delivery (doc 115 D-3): tombstone stays visible-pending
      // with the envelope retained until the deletion receipt arrives.
      return normalizeOutgoingDeleteTombstoneVisibility(
        tombstone.copyWith(
          status: 'inboxed',
          transport: 'inbox',
          wireEnvelope: jsonString,
        ),
      );
    }
  } catch (_) {
    // Fall through to the durable sent state.
  }

  return normalizeOutgoingDeleteTombstoneVisibility(
    tombstone.copyWith(
      status: 'sent',
      transport: via,
      wireEnvelope: jsonString,
    ),
  );
}

SendChatMessageResult _resultForDeleteFailureReason(String? reason) {
  return switch (reason) {
    'peer_not_found' => SendChatMessageResult.peerNotFound,
    'dial_failed' => SendChatMessageResult.dialFailed,
    _ => SendChatMessageResult.sendFailed,
  };
}

String _resolveDeleteTransport(
  P2PService p2pService,
  String peerId,
  SendMessageResult sendResult, {
  bool preserveLocalPeerLabel = false,
}) {
  if (preserveLocalPeerLabel && p2pService.isLocalPeer(peerId)) {
    return 'local';
  }

  final actualTransport = sendResult.transport;
  if (actualTransport != null && actualTransport.isNotEmpty) {
    return actualTransport;
  }

  final hasRelayConnection = p2pService.currentState.connections.any(
    (connection) =>
        connection.peerId == peerId &&
        connection.multiaddrs.any(
          (multiaddr) => multiaddr.contains('/p2p-circuit'),
        ),
  );
  return hasRelayConnection ? 'relay' : 'direct';
}

Future<_DeleteRaceResult> _tryLocalDeleteSend(
  P2PService p2pService,
  String targetPeerId,
  String jsonString,
  String senderPeerId, {
  required int timeoutMs,
}) async {
  final sent = await p2pService.sendLocalMessage(
    targetPeerId,
    jsonString,
    senderPeerId,
    timeoutMs: timeoutMs,
  );
  if (sent) {
    // WebSocket ownership is unauthenticated even when its receiver reports a
    // durable write. Keep it only as written evidence while libp2p can prove
    // target-peer delivery independently.
    return _DeleteRaceResult.succeeded(via: 'local', authenticated: false);
  }
  return _DeleteRaceResult.failed('local_send_failed');
}

Future<_DeleteRaceResult> _tryDirectDeleteSend(
  P2PService p2pService,
  String targetPeerId,
  String jsonString, {
  required OutgoingLiveDeadline liveDeadline,
}) async {
  final discoverTimeoutMs = liveDeadline.allocatePhaseTimeoutMs(
    outgoingDiscoverPhaseCap,
  );
  if (discoverTimeoutMs == null) {
    return _DeleteRaceResult.failed('peer_not_found', relayProbeEligible: true);
  }
  final peer = await p2pService.discoverPeer(
    targetPeerId,
    timeoutMs: discoverTimeoutMs,
  );
  if (peer == null) {
    return _DeleteRaceResult.failed('peer_not_found', relayProbeEligible: true);
  }

  final dialTimeoutMs = liveDeadline.allocatePhaseTimeoutMs(
    outgoingDialPhaseCap,
  );
  if (dialTimeoutMs == null) {
    return _DeleteRaceResult.failed('dial_failed', relayProbeEligible: true);
  }
  final dialed = await p2pService.dialPeer(
    targetPeerId,
    addresses: peer.addresses,
    timeoutMs: dialTimeoutMs,
  );
  if (!dialed) {
    return _DeleteRaceResult.failed('dial_failed', relayProbeEligible: true);
  }

  final sendTimeoutMs = liveDeadline.allocateCommittedSendTimeoutMs();
  if (sendTimeoutMs == null) {
    return _DeleteRaceResult.failed('direct_timeout');
  }
  final sendResult = await p2pService.sendMessageWithReply(
    targetPeerId,
    jsonString,
    timeoutMs: sendTimeoutMs,
  );
  if (!sendResult.sent) {
    return _DeleteRaceResult.failed('send_failed');
  }

  return _DeleteRaceResult.succeeded(
    via: _resolveDeleteTransport(p2pService, targetPeerId, sendResult),
    authenticated: true,
    explicitlyAcked: sendResult.acked == true,
  );
}

Future<_DeleteRaceResult> _tryRelayProbeDeleteSend(
  P2PService p2pService,
  String targetPeerId,
  String jsonString, {
  required String failureReason,
  required OutgoingLiveDeadline liveDeadline,
}) async {
  RelayProbeResult probeResult;
  try {
    final remaining = liveDeadline.remaining;
    if (remaining <= Duration.zero) {
      return _DeleteRaceResult.failed(failureReason);
    }
    probeResult = await p2pService.probeRelay(targetPeerId).timeout(remaining);
  } catch (_) {
    return _DeleteRaceResult.failed(failureReason);
  }

  switch (probeResult) {
    case RelayProbeResult.connected:
      try {
        final dialTimeoutMs = liveDeadline.allocatePhaseTimeoutMs(
          outgoingDialPhaseCap,
        );
        if (dialTimeoutMs != null) {
          await p2pService.dialPeer(targetPeerId, timeoutMs: dialTimeoutMs);
        }
      } catch (_) {}
      for (var attempt = 1; attempt <= relayProbeSendAttempts; attempt++) {
        try {
          final timeoutMs = liveDeadline.allocateCommittedSendTimeoutMs();
          if (timeoutMs == null) {
            return _DeleteRaceResult.failed('send_deadline_exhausted');
          }
          final sendResult = await p2pService.sendMessageWithReply(
            targetPeerId,
            jsonString,
            timeoutMs: timeoutMs,
          );
          if (sendResult.sent) {
            return _DeleteRaceResult.succeeded(
              via: _resolveDeleteTransport(
                p2pService,
                targetPeerId,
                sendResult,
              ),
              authenticated: true,
              explicitlyAcked: sendResult.acked == true,
            );
          }
        } catch (_) {}
        // NET-REL-05 P5: single post-probe send attempt
        // ([relayProbeSendAttempts] == 1); no inter-attempt backoff.
      }
      return _DeleteRaceResult.failed('send_failed');
    case RelayProbeResult.noReservation:
      return _DeleteRaceResult.failed('peer_not_found');
    case RelayProbeResult.error:
      return _DeleteRaceResult.failed(failureReason);
  }
}

bool _isOwnedMessageStoredPath(String storedPath, String messageId) {
  final normalized = storedPath.replaceAll('\\', '/');
  return normalized.startsWith('media/') ||
      normalized.startsWith('pending_uploads/$messageId/') ||
      normalized.contains('/media/') ||
      normalized.contains('/pending_uploads/$messageId/');
}

String _messageIdPreview(String id) => id.length > 8 ? id.substring(0, 8) : id;
