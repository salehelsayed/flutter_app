import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/text_sanitizer.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/direct_event_fanout_coordinator.dart';
import 'package:flutter_app/features/conversation/application/retry_failed_messages_use_case.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';
import 'package:flutter_app/features/posts/domain/thought_quote.dart';
import 'package:flutter_app/features/posts/domain/thought_reply_draft.dart';
import 'package:flutter_app/features/posts/domain/thought_reply_status.dart';
import 'package:uuid/uuid.dart';

/// Rechecks the retained original row and its current contact eligibility.
Future<bool> canSendThoughtReplyDuringGrace({
  required ThoughtReplyDraft draft,
  required PostRepository postRepo,
  required ContactRepository contactRepo,
  required DateTime Function() nowProvider,
}) async {
  final now = nowProvider().toUtc();
  if (!draft.isInGraceAt(now)) return false;
  final post = await postRepo.getRetainedIncomingPost(
    draft.postId,
    now.subtract(ThoughtReplyDraft.grace),
  );
  if (post == null || !draft.matches(post)) return false;
  final contact = await contactRepo.getContact(draft.authorPeerId);
  if (contact == null || contact.isBlocked || contact.isArchived) return false;
  final feed = await postRepo.loadFeed();
  return draft.isInGraceAt(nowProvider()) &&
      !feed.any((thought) {
        final expiry = DateTime.tryParse(thought.expiresAt);
        return expiry != null &&
            expiry.isAfter(now) &&
            draft.isSupersededBy(thought);
      });
}

/// Sends an ordinary encrypted chat reply; the calling surface owns navigation.
/// The card keeps [messageId] for Retry. Authored intent and transport custody
/// remain owned by the existing chat pipeline, including offline recovery.
Future<ThoughtReplyStatus> sendThoughtReply({
  required String messageId,
  required String postId,
  required String authorPeerId,
  required String text,
  required PostRepository postRepo,
  required MessageRepository messageRepo,
  required IdentityRepository identityRepo,
  required ContactRepository contactRepo,
  required P2PService p2pService,
  required Bridge bridge,
  DirectEventFanoutAuthoring? directEventFanout,
  DateTime Function()? nowProvider,
  String? expectedSenderPeerId,
  ThoughtReplyDraft? activeDraft,
}) async {
  final sanitized = sanitizeMessageText(text.trim());
  final quoteId = thoughtQuoteId(postId);
  if (messageId.isEmpty ||
      postId.isEmpty ||
      sanitized.isEmpty ||
      isMessageTooLong(sanitized)) {
    return ThoughtReplyStatus.failed;
  }
  try {
    final clock = nowProvider ?? DateTime.now;
    final post = await postRepo.getPost(postId);
    final now = clock().toUtc();
    final expiry = DateTime.tryParse(post?.expiresAt ?? '');
    final live =
        post != null &&
        post.isIncoming &&
        post.authorPeerId == authorPeerId &&
        expiry != null &&
        expiry.isAfter(now);
    if (!live &&
        (activeDraft == null ||
            activeDraft.postId != postId ||
            activeDraft.authorPeerId != authorPeerId ||
            !await canSendThoughtReplyDuringGrace(
              draft: activeDraft,
              postRepo: postRepo,
              contactRepo: contactRepo,
              nowProvider: clock,
            ))) {
      return ThoughtReplyStatus.failed;
    }
    final contact = await contactRepo.getContact(authorPeerId);
    final identity = await identityRepo.loadIdentity();
    if (contact == null ||
        contact.isBlocked ||
        contact.isArchived ||
        identity == null ||
        (expectedSenderPeerId != null &&
            identity.peerId != expectedSenderPeerId)) {
      return ThoughtReplyStatus.failed;
    }

    final existing = await messageRepo.getMessage(messageId);
    if (existing != null) {
      // Never reinterpret an edited/deleted message or reuse another action's
      // ID. A failed persisted send goes through the canonical exact retry.
      if (existing.isIncoming ||
          existing.isDeleted ||
          existing.isHidden ||
          existing.editedAt != null ||
          existing.contactPeerId != authorPeerId ||
          existing.senderPeerId != identity.peerId ||
          existing.quotedMessageId != quoteId ||
          existing.text != sanitized ||
          existing.media.isNotEmpty ||
          existing.privateMediaPolicy.requiresRedaction) {
        return ThoughtReplyStatus.failed;
      }
      if (existing.status == 'failed') {
        await retryFailedMessage(
          messageId: messageId,
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
        );
      }
      final current = await messageRepo.getMessage(messageId);
      return current == null
          ? ThoughtReplyStatus.failed
          : ThoughtReplyStatus.fromMessage(current);
    }

    if (messageRepo is! AuthoredDirectTextIntentRepository) {
      return ThoughtReplyStatus.failed;
    }
    final intents = messageRepo as AuthoredDirectTextIntentRepository;
    if (!intents.supportsAuthoredDirectTextIntents) {
      return ThoughtReplyStatus.failed;
    }
    var intent = (await intents.loadAuthoredDirectTextIntents())
        .where((entry) => entry.id == messageId)
        .firstOrNull;
    if (intent != null &&
        (intent.contactPeerId != authorPeerId ||
            intent.text != sanitized ||
            intent.quotedMessageId != quoteId)) {
      return ThoughtReplyStatus.failed;
    }
    if (intent == null) {
      final admissionTime = clock().toUtc();
      if ((expiry == null || !expiry.isAfter(admissionTime)) &&
          (activeDraft == null ||
              !await canSendThoughtReplyDuringGrace(
                draft: activeDraft,
                postRepo: postRepo,
                contactRepo: contactRepo,
                nowProvider: clock,
              ))) {
        return ThoughtReplyStatus.failed;
      }
      intent = AuthoredDirectTextIntent(
        id: messageId,
        contactPeerId: authorPeerId,
        text: sanitized,
        timestamp: now.toIso8601String(),
        token: const Uuid().v4(),
        quotedMessageId: quoteId,
      );
      if (!await intents.saveAuthoredDirectTextIntent(intent)) {
        return ThoughtReplyStatus.failed;
      }
    }
    final authoredIntent = intent;
    final (result, _) = await sendChatMessage(
      p2pService: p2pService,
      messageRepo: messageRepo,
      targetPeerId: authorPeerId,
      text: authoredIntent.text,
      senderPeerId: identity.peerId,
      senderUsername: identity.username,
      messageId: authoredIntent.id,
      preassignedMessageIdIsFresh: true,
      authoredTextIntentToken: authoredIntent.token,
      timestamp: authoredIntent.timestamp,
      bridge: bridge,
      recipientMlKemPublicKey: contact.mlKemPublicKey,
      quotedMessageId: authoredIntent.quotedMessageId,
      directEventFanout: directEventFanout,
    );
    final stored = await messageRepo.getMessage(messageId);
    if (stored != null) return ThoughtReplyStatus.fromMessage(stored);
    if (result == SendChatMessageResult.success) return ThoughtReplyStatus.sent;
    // This is a durable authored action, even if encryption/network setup has
    // not yet produced a visible message. The normal reconnect worker owns it.
    return (await intents.loadAuthoredDirectTextIntents()).any(
          (entry) =>
              entry.id == authoredIntent.id &&
              entry.token == authoredIntent.token,
        )
        ? ThoughtReplyStatus.queued
        : ThoughtReplyStatus.failed;
  } catch (_) {
    // The caller retains the same ID. Retry re-reads its durable authority;
    // an exception after staging cannot mint a duplicate user action.
    return ThoughtReplyStatus.failed;
  }
}
