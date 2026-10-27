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
import 'package:flutter_app/features/posts/domain/thought_reply_status.dart';
import 'package:uuid/uuid.dart';

/// Sends an ordinary encrypted chat reply without navigating away from a card.
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
}) async {
  final sanitized = sanitizeMessageText(text.trim());
  final quoteId = thoughtQuoteId(postId);
  if (messageId.isEmpty || postId.isEmpty || sanitized.isEmpty) {
    return ThoughtReplyStatus.failed;
  }
  try {
    final post = await postRepo.getPost(postId);
    final now = (nowProvider ?? DateTime.now)().toUtc();
    final expiry = DateTime.tryParse(post?.expiresAt ?? '');
    if (post == null ||
        !post.isIncoming ||
        post.authorPeerId != authorPeerId ||
        expiry == null ||
        !expiry.isAfter(now)) {
      return ThoughtReplyStatus.failed;
    }
    final contact = await contactRepo.getContact(authorPeerId);
    final identity = await identityRepo.loadIdentity();
    if (contact == null ||
        contact.isBlocked ||
        contact.isArchived ||
        identity == null) {
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
