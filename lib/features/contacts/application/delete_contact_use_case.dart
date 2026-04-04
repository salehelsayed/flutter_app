import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/features/contact_request/domain/repositories/contact_request_repository.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
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
    final candidateMessages = await _loadCandidateMessagesForCleanup(
      messageRepo: messageRepo,
      peerId: peerId,
    );

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

    final deletedCount = await messageRepo.deleteMessagesForContact(peerId);

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

    emitFlowEvent(
      layer: 'UC',
      event: 'DELETE_CONTACT_MESSAGES_PURGED',
      details: {'peerId': peerIdPreview, 'deletedMessages': deletedCount},
    );

    await contactRepo.deleteContact(peerId);

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
