import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';

const Duration interactivePostPinBudget = Duration(seconds: 4);

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

Future<bool> sendPostPinEnvelope({
  required P2PService p2pService,
  required List<String> recipientPeerIds,
  required String envelope,
}) async {
  var deliveredAny = false;
  for (final recipientPeerId in recipientPeerIds) {
    final sendResult = await p2pService.sendMessageWithReply(
      recipientPeerId,
      envelope,
      timeoutMs: interactivePostPinBudget.inMilliseconds,
    );
    if (sendResult.sent) {
      deliveredAny = true;
      continue;
    }
    final stored = await p2pService.storeInInbox(recipientPeerId, envelope);
    deliveredAny = deliveredAny || stored;
  }
  return deliveredAny;
}
