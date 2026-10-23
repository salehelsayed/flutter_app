import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/posts/application/post_follow_on_delivery.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';

const Duration interactivePostPinBudget = Duration(seconds: 4);
// Pins use a higher fanout cap than the prior serialized path so updates and
// removals do not stack behind one slow recipient.
const int defaultPostPinDeliveryConcurrency = 25;
const String postPinUpdateFollowOnEventType = 'post_pin_update';
const String postPinRemoveFollowOnEventType = 'post_pin_remove';

Future<List<String>> loadPostPinRecipients({
  required PostRepository postRepo,
  required String postId,
}) async {
  final deliveries = await postRepo.getRecipientDeliveries(postId);
  final recipients = <String>{
    for (final delivery in deliveries)
      if (delivery.recipientPeerId.isNotEmpty) delivery.recipientPeerId,
  };
  return recipients.toList(growable: false);
}

Future<List<PostMediaAttachmentModel>> loadRenderablePostPinMedia({
  required PostRepository postRepo,
  required PostModel post,
}) async {
  final media = post.media.isNotEmpty
      ? post.media
      : await postRepo.loadPostMediaAttachments(post.id);
  if (media.isEmpty) {
    return const <PostMediaAttachmentModel>[];
  }
  return media
      .map((attachment) => attachment.copyWith(postId: post.id))
      .toList(growable: false);
}

Future<PostFollowOnDeliveryResult> sendPostPinEnvelope({
  required P2PService p2pService,
  required List<String> recipientPeerIds,
  required String envelope,
  int maxConcurrentRecipients = defaultPostPinDeliveryConcurrency,
}) async {
  return fanoutPostFollowOnEnvelope(
    p2pService: p2pService,
    recipientPeerIds: recipientPeerIds,
    envelope: envelope,
    maxConcurrentRecipients: maxConcurrentRecipients,
    interactiveBudget: interactivePostPinBudget,
  );
}

bool isPostPinFollowOnEventType(String eventType) {
  return eventType == postPinUpdateFollowOnEventType ||
      eventType == postPinRemoveFollowOnEventType;
}
