import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/posts/application/post_follow_on_delivery.dart';
import 'package:flutter_app/features/posts/domain/models/post_follow_on_outbox_event.dart';
import 'package:flutter_app/features/posts/domain/models/post_follow_on_outbox_recipient_delivery.dart';
import 'package:flutter_app/features/posts/domain/models/post_view_envelope.dart';
import 'package:flutter_app/features/posts/domain/models/thought_view_receipt.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';
import 'package:flutter_app/features/posts/domain/repositories/thought_view_repository.dart';
import 'package:uuid/uuid.dart';

/// Called only after this exact card has actually been displayed. The local
/// first-view marker and encrypted durable outbox event commit together.
Future<void> publishThoughtView({
  required String postId,
  required String viewerPeerId,
  required PostRepository postRepo,
  required ContactRepository contactRepo,
  required P2PService p2pService,
  required Bridge bridge,
  DateTime Function()? nowProvider,
}) async {
  if (postRepo is! ThoughtViewRepository) return;
  final views = postRepo as ThoughtViewRepository;
  final post = await postRepo.getPost(postId);
  final now = (nowProvider ?? DateTime.now)().toUtc();
  final expiry = DateTime.tryParse(post?.expiresAt ?? '');
  final created = DateTime.tryParse(post?.createdAt ?? '');
  if (post == null ||
      !post.isIncoming ||
      viewerPeerId.isEmpty ||
      post.authorPeerId == viewerPeerId ||
      expiry == null ||
      !expiry.isAfter(now) ||
      created == null)
    return;
  final contact = await contactRepo.getContact(post.authorPeerId);
  final key = contact?.mlKemPublicKey;
  if (contact == null ||
      contact.isBlocked ||
      contact.isArchived ||
      key == null ||
      key.isEmpty)
    return;
  if ((await views.loadThoughtViews(
    postId,
  )).any((view) => view.viewerPeerId == viewerPeerId))
    return;
  final viewedAt = now.toIso8601String();
  final receipt = ThoughtViewReceipt(
    postId: postId,
    viewerPeerId: viewerPeerId,
    viewedAt: viewedAt,
  );
  final envelope = PostViewEnvelope(
    eventId: 'evt_${const Uuid().v4()}',
    receipt: receipt,
    postCreatedAt: created,
  );
  // Encryption is outside the SQLite transaction. No plaintext fallback.
  final wire = await envelope.toEncryptedJson(
    bridge: bridge,
    recipientMlKemPublicKey: key,
  );
  final currentContact = await contactRepo.getContact(post.authorPeerId);
  if (currentContact == null ||
      currentContact.isBlocked ||
      currentContact.isArchived)
    return;
  final delivery = PostFollowOnOutboxRecipientDelivery(
    eventId: envelope.eventId,
    recipientPeerId: post.authorPeerId,
    deliveryStatus: 'pending',
    deliveryPath: 'queued',
    createdAt: viewedAt,
    updatedAt: viewedAt,
  );
  final queued = await views.queueThoughtView(
    receipt: receipt,
    event: PostFollowOnOutboxEvent(
      eventId: envelope.eventId,
      eventType: PostViewEnvelope.type,
      postId: postId,
      senderPeerId: viewerPeerId,
      rawEnvelope: wire,
      createdAt: viewedAt,
    ),
    recipient: delivery,
    authorPeerId: post.authorPeerId,
    nowIso: (nowProvider ?? DateTime.now)().toUtc().toIso8601String(),
  );
  if (!queued) return;
  // The ordinary follow-on worker owns any recipient not reached now.
  await deliverQueuedPostFollowOn(
    postRepo: postRepo,
    p2pService: p2pService,
    eventId: envelope.eventId,
    envelope: wire,
    deliveries: [delivery],
  );
}
