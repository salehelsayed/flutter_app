import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/media/direct_private_media_transfer_registry.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/private_media_lifecycle_engine.dart';
import 'package:flutter_app/features/contact_request/domain/repositories/contact_request_repository.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/contacts/domain/repositories/direct_contact_conversation_purge.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/application/direct_private_media_lifecycle.dart';
import 'package:flutter_app/features/conversation/domain/repositories/direct_private_media_lifecycle_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/introduction/domain/repositories/introduction_repository.dart';

/// Deletes a contact, all conversation rows, and related local state.
Future<void> deleteContactAndMessages({
  required ContactRepository contactRepo,
  required MessageRepository messageRepo,
  required String peerId,
  MediaAttachmentRepository? mediaAttachmentRepo,
  ReactionRepository? reactionRepo,
  MediaFileManager? mediaFileManager,
  ContactRequestRepository? contactRequestRepo,
  IntroductionRepository? introductionRepo,
}) async {
  final peerIdPreview = peerId.length > 10 ? peerId.substring(0, 10) : peerId;

  emitFlowEvent(
    layer: 'UC',
    event: 'DELETE_CONTACT_START',
    details: {'peerId': peerIdPreview},
  );

  try {
    final lifecycleRepository =
        messageRepo is DirectPrivateMediaLifecycleRepository
        ? messageRepo as DirectPrivateMediaLifecycleRepository
        : null;
    final cleanupRuntime =
        mediaAttachmentRepo is DirectPrivateMediaCleanupRuntime
        ? mediaAttachmentRepo as DirectPrivateMediaCleanupRuntime
        : null;
    final cleanupRepository =
        mediaAttachmentRepo is DirectPrivateMediaCleanupRepository
        ? mediaAttachmentRepo as DirectPrivateMediaCleanupRepository
        : null;

    // 361: the final DB decision converges messages, reactions, v108/v109
    // sibling rows, roster and contact in ONE serialized transaction when the
    // contact repository owns that capability. Everything BEFORE it — files,
    // keys, attachments, introductions, requests, and the best-effort early
    // reaction sweep — stays an early cleanup that must never physically
    // purge messages first.
    final purgeCapability =
        contactRepo is DirectContactConversationPurgeCapability
        ? contactRepo as DirectContactConversationPurgeCapability
        : null;
    final finalPurge =
        (purgeCapability?.supportsDirectContactConversationPurge ?? false)
        ? purgeCapability
        : null;

    Future<void> purgeRelatedState(
      List<ConversationMessage> candidateMessages,
    ) async {
      await _deleteLocalMediaArtifacts(
        mediaFileManager: mediaFileManager,
        peerId: peerId,
        candidateMessages: candidateMessages,
      );

      final deletedReactionCount =
          await reactionRepo?.deleteReactionsForContact(peerId) ?? 0;
      final deletedAttachmentCount =
          await mediaAttachmentRepo?.deleteAttachmentsForContact(peerId) ?? 0;
      final deletedIntroductionCount = await _deleteIntroductionsForPeer(
        introRepo: introductionRepo,
        peerId: peerId,
      );
      if (contactRequestRepo != null) {
        await contactRequestRepo.deleteRequest(peerId);
      }

      emitFlowEvent(
        layer: 'UC',
        event: 'DELETE_CONTACT_RELATED_STATE_PURGED',
        details: {
          'peerId': peerIdPreview,
          'deletedReactions': deletedReactionCount,
          'deletedAttachments': deletedAttachmentCount,
          'deletedIntroductions': deletedIntroductionCount,
        },
      );

      if (finalPurge != null) {
        final summary = await finalPurge
            .purgeDirectContactConversationAndContact(peerId);
        emitFlowEvent(
          layer: 'UC',
          event: 'DELETE_CONTACT_FINAL_PURGE_COMMITTED',
          details: {
            'peerId': peerIdPreview,
            'deletedMessages': summary.deletedMessages,
            'deletedReactions': summary.deletedReactions,
            'deletedTextCustodyRows': summary.deletedTextCustodyRows,
            'deletedEventCustodyRows': summary.deletedEventCustodyRows,
          },
        );
        if (messageRepo is DirectContactPurgeReconciliation) {
          await (messageRepo as DirectContactPurgeReconciliation)
              .reconcileDirectContactConversationPurge(peerId);
        }
        if (reactionRepo is DirectContactPurgeReconciliation) {
          await (reactionRepo as DirectContactPurgeReconciliation)
              .reconcileDirectContactConversationPurge(peerId);
        }
        return;
      }

      final deletedCount = await messageRepo.deleteMessagesForContact(peerId);

      emitFlowEvent(
        layer: 'UC',
        event: 'DELETE_CONTACT_MESSAGES_PURGED',
        details: {'peerId': peerIdPreview, 'deletedMessages': deletedCount},
      );

      await contactRepo.deleteContact(peerId);
    }

    Future<void> deleteInventoriedState(
      List<ConversationMessage> candidateMessages,
    ) async {
      final privateCandidates = candidateMessages
          .where((message) => message.privateMediaPolicy.requiresRedaction)
          .toList(growable: false);
      if (privateCandidates.isNotEmpty &&
          (lifecycleRepository == null ||
              cleanupRuntime == null ||
              cleanupRepository == null ||
              mediaFileManager == null)) {
        throw StateError(
          'private contact deletion requires terminal lifecycle cleanup',
        );
      }

      final currentPrivateMessages = <ConversationMessage>[];
      for (final candidate in privateCandidates) {
        final current = await messageRepo.getMessage(candidate.id);
        if (current == null ||
            current.contactPeerId != peerId ||
            !current.privateMediaPolicy.requiresRedaction) {
          throw StateError(
            'private contact deletion authority changed before cleanup',
          );
        }
        currentPrivateMessages.add(current);
      }

      // Destructive contact deletion is all-or-nothing with respect to live
      // transfer custody. The global registry check also covers a scoped
      // transfer whose parent appeared after a previous inventory (or whose
      // parent was already removed). Contact deletion is rare enough that
      // conservatively deferring for an unrelated direct-private transfer is
      // preferable to deleting the only authority for in-flight bytes.
      if (directPrivateMediaTransferRegistry.hasAnyActive) {
        throw StateError('private contact deletion blocked by active transfer');
      }
      for (final current in currentPrivateMessages) {
        final attachments = await mediaAttachmentRepo!.getAttachmentsForMessage(
          current.id,
          owner: MediaOwnerLane.direct,
        );
        for (final attachment in attachments) {
          if (attachment.messageId != current.id ||
              (attachment.ownerLane != null &&
                  attachment.ownerLane != MediaOwnerLane.direct)) {
            throw StateError(
              'private contact deletion attachment authority changed',
            );
          }
        }
      }

      final now = DateTime.now().toUtc();
      for (final current in currentPrivateMessages) {
        final alreadyTerminal =
            current.isHidden ||
            current.isDeleted ||
            current.privateMediaState.isTerminal ||
            current.privateMediaTerminalAtMs != null;
        if (alreadyTerminal) {
          continue;
        }
        final hidden = await lifecycleRepository!.hidePrivateMediaForMe(
          current.id,
          hiddenAt: now.toIso8601String(),
          nowMs: now.millisecondsSinceEpoch,
        );
        if (!hidden) {
          throw StateError(
            'private contact deletion could not terminalize ${current.id}',
          );
        }
      }

      if (currentPrivateMessages.isNotEmpty) {
        final adapter = DirectPrivateMediaLifecycle(
          messageRepository: lifecycleRepository!,
          mediaAttachmentRepository: mediaAttachmentRepo!,
          mediaFileManager: mediaFileManager!,
        );
        final engine = PrivateMediaLifecycleEngine(
          adapter: adapter,
          lifecycleLock: cleanupRuntime!.directPrivateMediaLifecycleLock,
          nowMs: () => DateTime.now().toUtc().millisecondsSinceEpoch,
        );
        for (final current in currentPrivateMessages) {
          await engine.cleanupTerminalMessage(current.id);
        }
      }
      await purgeRelatedState(candidateMessages);
    }

    final runtime = cleanupRuntime;
    if (runtime != null) {
      // Inventory only after acquiring the same global authority used by every
      // direct-private attachment writer. This closes the empty-inventory race:
      // a first-row insert started during deletion queues behind this operation,
      // then requalifies against the deleted/terminal parent and refuses.
      await runtime.directPrivateMediaLifecycleLock.synchronizedAll(() async {
        final candidateMessages = await _loadCandidateMessagesForCleanup(
          messageRepo: messageRepo,
          peerId: peerId,
        );
        await deleteInventoriedState(candidateMessages);
      });
    } else {
      final candidateMessages = await _loadCandidateMessagesForCleanup(
        messageRepo: messageRepo,
        peerId: peerId,
      );
      await deleteInventoriedState(candidateMessages);
    }

    emitFlowEvent(
      layer: 'UC',
      event: 'DELETE_CONTACT_SUCCESS',
      details: {'peerId': peerIdPreview},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'UC',
      event: 'DELETE_CONTACT_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

Future<List<ConversationMessage>> _loadCandidateMessagesForCleanup({
  required MessageRepository messageRepo,
  required String peerId,
}) async {
  final byId = <String, ConversationMessage>{};

  void remember(Iterable<ConversationMessage> messages) {
    for (final message in messages) {
      if (message.contactPeerId != peerId) {
        continue;
      }
      byId[message.id] = message;
    }
  }

  remember(await messageRepo.getMessagesForContact(peerId));
  remember(await messageRepo.getFailedOutgoingMessages());
  remember(
    await messageRepo.getUnackedOutgoingMessages(olderThan: Duration.zero),
  );
  remember(await messageRepo.getSendingOutgoingMessages());
  if (messageRepo is DirectPrivateMediaLifecycleRepository) {
    final lifecycleRepository =
        messageRepo as DirectPrivateMediaLifecycleRepository;
    // Recovery candidates include hidden/deleted terminal parents whose
    // attachment cleanup was interrupted. Contact deletion must see those
    // rows too; otherwise a retry could delete the parent/contact while
    // leaving a key/file/attachment orphan. The SQL LIMIT maximum makes this
    // an exhaustive, rare destructive-operation read rather than the bounded
    // startup cleanup page.
    remember(
      await lifecycleRepository.loadPrivateMediaRecoveryCandidates(
        limit: 0x7fffffff,
      ),
    );
  }

  return byId.values.toList(growable: false);
}

Future<void> _deleteLocalMediaArtifacts({
  required MediaFileManager? mediaFileManager,
  required String peerId,
  required List<ConversationMessage> candidateMessages,
}) async {
  if (mediaFileManager == null) {
    return;
  }

  for (final message in candidateMessages) {
    await mediaFileManager.deletePendingUploadDir(message.id);
  }

  await mediaFileManager.deleteMediaForContact(peerId);
}

Future<int> _deleteIntroductionsForPeer({
  required IntroductionRepository? introRepo,
  required String peerId,
}) async {
  if (introRepo == null) {
    return 0;
  }

  final introductions = <String, IntroductionModel>{};
  final introLists = await Future.wait([
    introRepo.getIntroductionsByRecipient(peerId),
    introRepo.getIntroductionsByIntroduced(peerId),
    introRepo.getIntroductionsByIntroducer(peerId),
  ]);

  for (final introList in introLists) {
    for (final intro in introList) {
      introductions[intro.id] = intro;
    }
  }

  for (final intro in introductions.values) {
    await introRepo.deleteIntroduction(intro.id);
  }

  return introductions.length;
}
